// Package web provides the main web server implementation for the 3x-ui panel,
// including HTTP/HTTPS serving, routing, templates, and background job scheduling.
package web

import (
	"context"
	"crypto/tls"
	"embed"
	"html/template"
	"io"
	"io/fs"
	"net"
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/mhsanaei/3x-ui/v2/config"
	"github.com/mhsanaei/3x-ui/v2/logger"
	"github.com/mhsanaei/3x-ui/v2/util/common"
	"github.com/mhsanaei/3x-ui/v2/web/controller"
	"github.com/mhsanaei/3x-ui/v2/web/job"
	"github.com/mhsanaei/3x-ui/v2/web/locale"
	"github.com/mhsanaei/3x-ui/v2/web/middleware"
	"github.com/mhsanaei/3x-ui/v2/web/network"
	"github.com/mhsanaei/3x-ui/v2/web/service"

	"github.com/gin-contrib/gzip"
	"github.com/gin-contrib/sessions"
	"github.com/gin-contrib/sessions/cookie"
	"github.com/gin-gonic/gin"
	"github.com/robfig/cron/v3"
)

//go:embed assets
var assetsFS embed.FS

//go:embed html/*
var htmlFS embed.FS

//go:embed translation/*
var i18nFS embed.FS

var startTime = time.Now()

type wrapAssetsFS struct {
	embed.FS
}

func (f *wrapAssetsFS) Open(name string) (fs.File, error) {
	file, err := f.FS.Open("assets/" + name)
	if err != nil {
		return nil, err
	}
	return &wrapAssetsFile{
		File: file,
	}, nil
}

type wrapAssetsFile struct {
	fs.File
}

func (f *wrapAssetsFile) Stat() (fs.FileInfo, error) {
	info, err := f.File.Stat()
	if err != nil {
		return nil, err
	}
	return &wrapAssetsFileInfo{
		FileInfo: info,
	}, nil
}

type wrapAssetsFileInfo struct {
	fs.FileInfo
}

func (f *wrapAssetsFileInfo) ModTime() time.Time {
	return startTime
}

// EmbeddedHTML returns the embedded HTML templates filesystem for reuse by other servers.
func EmbeddedHTML() embed.FS {
	return htmlFS
}

// EmbeddedAssets returns the embedded assets filesystem for reuse by other servers.
func EmbeddedAssets() embed.FS {
	return assetsFS
}

// Server represents the main web server for the 3x-ui panel with controllers, services, and scheduled jobs.
type Server struct {
	httpServer *http.Server
	listener   net.Listener

	index *controller.IndexController
	panel *controller.XUIController
	api   *controller.APIController

	xrayService    service.XrayService
	settingService service.SettingService
	tgbotService   service.Tgbot

	cron *cron.Cron

	ctx    context.Context
	cancel context.CancelFunc
}

// NewServer creates a new web server instance with a cancellable context.
func NewServer() *Server {
	ctx, cancel := context.WithCancel(context.Background())
	return &Server{
		ctx:    ctx,
		cancel: cancel,
	}
}

// getHtmlFiles walks the local `web/html` directory and returns a list of
// template file paths. Used only in debug/development mode.
func (s *Server) getHtmlFiles() ([]string, error) {
	files := make([]string, 0)
	dir, _ := os.Getwd()
	err := fs.WalkDir(os.DirFS(dir), "web/html", func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if d.IsDir() {
			return nil
		}
		files = append(files, path)
		return nil
	})
	if err != nil {
		return nil, err
	}
	return files, nil
}

// getHtmlTemplate parses embedded HTML templates from the bundled `htmlFS`
// using the provided template function map and returns the resulting
// template set for production usage.
func (s *Server) getHtmlTemplate(funcMap template.FuncMap) (*template.Template, error) {
	// Collect all HTML file paths
	var templatePaths []string
	err := fs.WalkDir(htmlFS, "html", func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if !d.IsDir() && strings.HasSuffix(path, ".html") {
			templatePaths = append(templatePaths, path)
		}
		return nil
	})
	if err != nil {
		return nil, err
	}

	// Parse all templates at once using ParseFS
	// This ensures template includes work correctly
	t, err := template.New("").Funcs(funcMap).ParseFS(htmlFS, templatePaths...)
	if err != nil {
		return nil, err
	}

	// Log all parsed template names for debugging
	logger.Info("Parsed", len(t.Templates()), "templates")
	// Log template names to see what ParseFS actually creates
	for _, tmpl := range t.Templates() {
		name := tmpl.Name()
		if name != "" && (strings.HasSuffix(name, "nodes.html") || strings.HasSuffix(name, "index.html") || strings.HasSuffix(name, "map.html") || strings.HasSuffix(name, "multi_subscriptions.html")) {
			logger.Info("Found template with name:", name)
		}
	}

	// Check for required template definitions
	requiredDefs := []string{"page/head_start", "page/head_end", "page/body_start", "page/body_end", "page/body_scripts"}
	for _, defName := range requiredDefs {
		if t.Lookup(defName) == nil {
			logger.Warning("Required template definition not found:", defName)
		} else {
			logger.Info("Template definition found:", defName)
		}
	}

	// ParseFS creates template names with full paths like "html/nodes.html"
	// But Gin expects short names like "nodes.html"
	// We need to create aliases for root templates
	var rootTemplates []struct {
		fullName  string
		shortName string
	}
	for _, tmpl := range t.Templates() {
		name := tmpl.Name()
		if name != "" && strings.HasPrefix(name, "html/") && !strings.Contains(name[len("html/"):], "/") {
			shortName := name[len("html/"):]
			rootTemplates = append(rootTemplates, struct {
				fullName  string
				shortName string
			}{fullName: name, shortName: shortName})
		}
	}

	// Add aliases for root templates
	logger.Info("Found", len(rootTemplates), "root templates to process")
	for _, rt := range rootTemplates {
		logger.Info("Processing root template:", rt.fullName, "->", rt.shortName)
		if t.Lookup(rt.shortName) == nil {
			origTmpl := t.Lookup(rt.fullName)
			if origTmpl != nil {
				_, err := t.AddParseTree(rt.shortName, origTmpl.Tree)
				if err != nil {
					logger.Warning("Failed to add template alias:", rt.fullName, "->", rt.shortName, err)
				} else {
					logger.Info("Added template alias:", rt.fullName, "->", rt.shortName)
					// Verify the alias works
					if aliasTmpl := t.Lookup(rt.shortName); aliasTmpl != nil {
						logger.Info("Alias verified:", rt.shortName)
					} else {
						logger.Warning("Alias NOT verified:", rt.shortName)
					}
				}
			} else {
				logger.Warning("Original template not found for alias:", rt.fullName)
			}
		} else {
			logger.Info("Template already exists with short name:", rt.shortName)
		}
	}

	// Verify that templates can be found by short names
	logger.Info("Verifying template lookup by short names:")
	for _, reqName := range []string{"nodes.html", "multi_subscriptions.html", "map.html", "index.html", "xray.html", "inbounds.html"} {
		if t.Lookup(reqName) == nil {
			logger.Warning("Template NOT found by short name:", reqName)
		} else {
			logger.Info("Template found by short name:", reqName)
		}
	}

	// Verify that required templates exist and can be executed
	requiredTemplates := []string{"nodes.html", "multi_subscriptions.html", "map.html", "index.html", "login.html"}
	// Also verify component templates are available
	componentTemplates := []string{"component/aSidebar", "component/aThemeSwitch", "component/themeSwitchTemplate"}
	for _, compName := range componentTemplates {
		if t.Lookup(compName) == nil {
			logger.Warning("Component template not found:", compName)
		} else {
			logger.Info("Component template found:", compName)
		}
	}

	for _, reqName := range requiredTemplates {
		if t.Lookup(reqName) == nil {
			logger.Warning("Required template not found:", reqName)
		} else {
			logger.Info("Template found:", reqName)
			// Try to execute the template to check for errors
			var buf strings.Builder
			testData := gin.H{
				"base_path":   "/",
				"cur_ver":     "test",
				"host":        "test",
				"title":       "test",
				"request_uri": "/test",
			}
			err := t.ExecuteTemplate(&buf, reqName, testData)
			if err != nil {
				logger.Warning("Template execution test failed for", reqName, ":", err)
				logger.Warning("Error details:", err.Error())
			} else {
				logger.Info("Template execution test passed for", reqName, "output length:", buf.Len())
				if buf.Len() == 0 {
					logger.Warning("Template", reqName, "executed but produced empty output!")
				}
				// For problematic templates, check if component templates are included in output
				if reqName == "nodes.html" || reqName == "multi_subscriptions.html" || reqName == "map.html" {
					output := buf.String()
					if !strings.Contains(output, "a-theme-switch") {
						logger.Warning("Template", reqName, "output does not contain 'a-theme-switch' component")
					}
					if !strings.Contains(output, "a-sidebar") {
						logger.Warning("Template", reqName, "output does not contain 'a-sidebar' component")
					}
					if !strings.Contains(output, "Vue.component") {
						logger.Warning("Template", reqName, "output does not contain 'Vue.component' registration")
					}
				}
			}
		}
	}

	return t, nil
}

// initRouter
// initRouter initializes Gin, registers middleware, templates, static
// assets, controllers and returns the configured engine.
func (s *Server) initRouter() (*gin.Engine, error) {
	if config.IsDebug() {
		gin.SetMode(gin.DebugMode)
	} else {
		gin.DefaultWriter = io.Discard
		gin.DefaultErrorWriter = io.Discard
		gin.SetMode(gin.ReleaseMode)
	}

	engine := gin.Default()

	webDomain, err := s.settingService.GetWebDomain()
	if err != nil {
		return nil, err
	}

	if webDomain != "" {
		engine.Use(middleware.DomainValidatorMiddleware(webDomain))
	}

	secret, err := s.settingService.GetSecret()
	if err != nil {
		return nil, err
	}

	basePath, err := s.settingService.GetBasePath()
	if err != nil {
		return nil, err
	}
	engine.Use(gzip.Gzip(gzip.DefaultCompression, gzip.WithExcludedPaths([]string{basePath + "panel/api/"})))
	assetsBasePath := basePath + "assets/"

	store := cookie.NewStore(secret)
	// Configure default session cookie options, including expiration (MaxAge)
	if sessionMaxAge, err := s.settingService.GetSessionMaxAge(); err == nil {
		store.Options(sessions.Options{
			Path:     "/",
			MaxAge:   sessionMaxAge * 60, // minutes -> seconds
			HttpOnly: true,
			SameSite: http.SameSiteLaxMode,
		})
	}
	engine.Use(sessions.Sessions("3x-ui", store))
	engine.Use(func(c *gin.Context) {
		c.Set("base_path", basePath)
	})
	engine.Use(func(c *gin.Context) {
		uri := c.Request.RequestURI
		if strings.HasPrefix(uri, assetsBasePath) {
			c.Header("Cache-Control", "max-age=31536000")
		}
	})

	// init i18n
	err = locale.InitLocalizer(i18nFS, &s.settingService)
	if err != nil {
		return nil, err
	}

	// Apply locale middleware for i18n
	i18nWebFunc := func(key string, params ...string) string {
		return locale.I18n(locale.Web, key, params...)
	}
	// Register template functions before loading templates
	funcMap := template.FuncMap{
		"i18n": i18nWebFunc,
	}
	engine.SetFuncMap(funcMap)
	engine.Use(locale.LocalizerMiddleware())

	// set static files and template
	if config.IsDebug() {
		// for development
		files, err := s.getHtmlFiles()
		if err != nil {
			return nil, err
		}
		// Use the registered func map with the loaded templates
		engine.LoadHTMLFiles(files...)
		engine.StaticFS(basePath+"assets", http.FS(os.DirFS("web/assets")))
	} else {
		// for production
		template, err := s.getHtmlTemplate(funcMap)
		if err != nil {
			return nil, err
		}
		engine.SetHTMLTemplate(template)
		engine.StaticFS(basePath+"assets", http.FS(&wrapAssetsFS{FS: assetsFS}))
	}

	// Apply the redirect middleware (`/xui` to `/panel`)
	engine.Use(middleware.RedirectMiddleware(basePath))

	g := engine.Group(basePath)

	s.index = controller.NewIndexController(g)
	s.panel = controller.NewXUIController(g)
	s.api = controller.NewAPIController(g)

	// Chrome DevTools endpoint for debugging web apps
	engine.GET("/.well-known/appspecific/com.chrome.devtools.json", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{})
	})

	// Add a catch-all route to handle undefined paths and return 404
	engine.NoRoute(func(c *gin.Context) {
		c.AbortWithStatus(http.StatusNotFound)
	})

	return engine, nil
}

// startTask schedules background jobs (Xray checks, traffic jobs, cron
// jobs) which the panel relies on for periodic maintenance and monitoring.
func (s *Server) startTask() {
	err := s.xrayService.RestartXray(true)
	if err != nil {
		logger.Warning("start xray failed:", err)
	}
	// Check whether xray is running every second
	s.cron.AddJob("@every 1s", job.NewCheckXrayRunningJob())

	// Check if xray needs to be restarted every 30 seconds
	s.cron.AddFunc("@every 30s", func() {
		if s.xrayService.IsNeedRestartAndSetFalse() {
			err := s.xrayService.RestartXray(false)
			if err != nil {
				logger.Error("restart xray failed:", err)
			}
		}
	})

	go func() {
		time.Sleep(time.Second * 5)
		// Statistics every 10 seconds, start the delay for 5 seconds for the first time, and staggered with the time to restart xray
		s.cron.AddJob("@every 10s", job.NewXrayTrafficJob())
	}()

	// check client ips from log file every 10 sec
	s.cron.AddJob("@every 10s", job.NewCheckClientIpJob())

	// check client ips from log file every day
	s.cron.AddJob("@daily", job.NewClearLogsJob())

	// Inbound traffic reset jobs
	// Run once a day, midnight
	s.cron.AddJob("@daily", job.NewPeriodicTrafficResetJob("daily"))
	// Run once a week, midnight between Sat/Sun
	s.cron.AddJob("@weekly", job.NewPeriodicTrafficResetJob("weekly"))
	// Run once a month, midnight, first of month
	s.cron.AddJob("@monthly", job.NewPeriodicTrafficResetJob("monthly"))

	// LDAP sync scheduling
	if ldapEnabled, _ := s.settingService.GetLdapEnable(); ldapEnabled {
		runtime, err := s.settingService.GetLdapSyncCron()
		if err != nil || runtime == "" {
			runtime = "@every 1m"
		}
		j := job.NewLdapSyncJob()
		// job has zero-value services with method receivers that read settings on demand
		s.cron.AddJob(runtime, j)
	}

	// Nodes: periodic status checks and stats sync
	// Check status every 30s
	s.cron.AddJob("@every 30s", job.NewNodeStatusJob())
	// Sync stats every 2 minutes
	s.cron.AddJob("@every 2m", job.NewNodeSyncJob())

	// Make a traffic condition every day, 8:30
	var entry cron.EntryID
	isTgbotenabled, err := s.settingService.GetTgbotEnabled()
	if (err == nil) && (isTgbotenabled) {
		runtime, err := s.settingService.GetTgbotRuntime()
		if err != nil || runtime == "" {
			logger.Errorf("Add NewStatsNotifyJob error[%s], Runtime[%s] invalid, will run default", err, runtime)
			runtime = "@daily"
		}
		logger.Infof("Tg notify enabled,run at %s", runtime)
		_, err = s.cron.AddJob(runtime, job.NewStatsNotifyJob())
		if err != nil {
			logger.Warning("Add NewStatsNotifyJob error", err)
			return
		}

		// check for Telegram bot callback query hash storage reset
		s.cron.AddJob("@every 2m", job.NewCheckHashStorageJob())

		// Check CPU load and alarm to TgBot if threshold passes
		cpuThreshold, err := s.settingService.GetTgCpu()
		if (err == nil) && (cpuThreshold > 0) {
			s.cron.AddJob("@every 10s", job.NewCheckCpuJob())
		}
	} else {
		s.cron.Remove(entry)
	}
}

// Start initializes and starts the web server with configured settings, routes, and background jobs.
func (s *Server) Start() (err error) {
	// This is an anonymous function, no function name
	defer func() {
		if err != nil {
			s.Stop()
		}
	}()

	loc, err := s.settingService.GetTimeLocation()
	if err != nil {
		return err
	}
	s.cron = cron.New(cron.WithLocation(loc), cron.WithSeconds())
	s.cron.Start()

	engine, err := s.initRouter()
	if err != nil {
		return err
	}

	certFile, err := s.settingService.GetCertFile()
	if err != nil {
		return err
	}
	keyFile, err := s.settingService.GetKeyFile()
	if err != nil {
		return err
	}
	listen, err := s.settingService.GetListen()
	if err != nil {
		return err
	}
	port, err := s.settingService.GetPort()
	if err != nil {
		return err
	}
	listenAddr := net.JoinHostPort(listen, strconv.Itoa(port))
	listener, err := net.Listen("tcp", listenAddr)
	if err != nil {
		return err
	}
	if certFile != "" || keyFile != "" {
		cert, err := tls.LoadX509KeyPair(certFile, keyFile)
		if err == nil {
			c := &tls.Config{
				Certificates: []tls.Certificate{cert},
			}
			listener = network.NewAutoHttpsListener(listener)
			listener = tls.NewListener(listener, c)
			logger.Info("Web server running HTTPS on", listener.Addr())
		} else {
			logger.Error("Error loading certificates:", err)
			logger.Info("Web server running HTTP on", listener.Addr())
		}
	} else {
		logger.Info("Web server running HTTP on", listener.Addr())
	}
	s.listener = listener

	s.httpServer = &http.Server{
		Handler: engine,
	}

	go func() {
		s.httpServer.Serve(listener)
	}()

	s.startTask()

	isTgbotenabled, err := s.settingService.GetTgbotEnabled()
	if (err == nil) && (isTgbotenabled) {
		tgBot := s.tgbotService.NewTgbot()
		tgBot.Start(i18nFS)
	}

	return nil
}

// Stop gracefully shuts down the web server, stops Xray, cron jobs, and Telegram bot.
func (s *Server) Stop() error {
	s.cancel()
	s.xrayService.StopXray()
	if s.cron != nil {
		s.cron.Stop()
	}
	if s.tgbotService.IsRunning() {
		s.tgbotService.Stop()
	}
	var err1 error
	var err2 error
	if s.httpServer != nil {
		err1 = s.httpServer.Shutdown(s.ctx)
	}
	if s.listener != nil {
		err2 = s.listener.Close()
	}
	return common.Combine(err1, err2)
}

// GetCtx returns the server's context for cancellation and deadline management.
func (s *Server) GetCtx() context.Context {
	return s.ctx
}

// GetCron returns the server's cron scheduler instance.
func (s *Server) GetCron() *cron.Cron {
	return s.cron
}
