package controller

import (
	"bufio"
	"net"
	"net/http"
	"strings"

	"github.com/mhsanaei/3x-ui/v2/config"
	"github.com/mhsanaei/3x-ui/v2/logger"
	"github.com/mhsanaei/3x-ui/v2/web/entity"

	"github.com/gin-gonic/gin"
)

// responseWriterWrapper wraps gin.ResponseWriter to intercept writes
type responseWriterWrapper struct {
	gin.ResponseWriter
	onWrite      func([]byte) (int, error)
	totalWritten int
}

func (w *responseWriterWrapper) Write(p []byte) (int, error) {
	w.totalWritten += len(p)
	if w.onWrite != nil {
		return w.onWrite(p)
	}
	return w.ResponseWriter.Write(p)
}

// Delegate all other ResponseWriter methods to the underlying writer
func (w *responseWriterWrapper) WriteHeader(statusCode int) {
	w.ResponseWriter.WriteHeader(statusCode)
}

func (w *responseWriterWrapper) WriteString(s string) (int, error) {
	w.totalWritten += len(s)
	if w.onWrite != nil {
		w.onWrite([]byte(s))
	}
	return w.ResponseWriter.WriteString(s)
}

func (w *responseWriterWrapper) Status() int {
	return w.ResponseWriter.Status()
}

func (w *responseWriterWrapper) Size() int {
	return w.ResponseWriter.Size()
}

func (w *responseWriterWrapper) Written() bool {
	return w.ResponseWriter.Written()
}

func (w *responseWriterWrapper) Header() http.Header {
	return w.ResponseWriter.Header()
}

func (w *responseWriterWrapper) Hijack() (net.Conn, *bufio.ReadWriter, error) {
	return w.ResponseWriter.Hijack()
}

func (w *responseWriterWrapper) CloseNotify() <-chan bool {
	return w.ResponseWriter.CloseNotify()
}

func (w *responseWriterWrapper) Flush() {
	w.ResponseWriter.Flush()
}

func (w *responseWriterWrapper) Pusher() http.Pusher {
	return w.ResponseWriter.Pusher()
}

func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}

// getRemoteIp extracts the real IP address from the request headers or remote address.
func getRemoteIp(c *gin.Context) string {
	value := c.GetHeader("X-Real-IP")
	if value != "" {
		return value
	}
	value = c.GetHeader("X-Forwarded-For")
	if value != "" {
		ips := strings.Split(value, ",")
		return ips[0]
	}
	addr := c.Request.RemoteAddr
	ip, _, _ := net.SplitHostPort(addr)
	return ip
}

// jsonMsg sends a JSON response with a message and error status.
func jsonMsg(c *gin.Context, msg string, err error) {
	jsonMsgObj(c, msg, nil, err)
}

// jsonObj sends a JSON response with an object and error status.
func jsonObj(c *gin.Context, obj any, err error) {
	jsonMsgObj(c, "", obj, err)
}

// jsonMsgObj sends a JSON response with a message, object, and error status.
func jsonMsgObj(c *gin.Context, msg string, obj any, err error) {
	m := entity.Msg{
		Obj: obj,
	}
	if err == nil {
		m.Success = true
		if msg != "" {
			m.Msg = msg
		}
	} else {
		m.Success = false
		m.Msg = msg + " (" + err.Error() + ")"
		logger.Warning(msg+" "+I18nWeb(c, "fail")+": ", err)
	}
	c.JSON(http.StatusOK, m)
}

// pureJsonMsg sends a pure JSON message response with custom status code.
func pureJsonMsg(c *gin.Context, statusCode int, success bool, msg string) {
	c.JSON(statusCode, entity.Msg{
		Success: success,
		Msg:     msg,
	})
}

// html renders an HTML template with the provided data and title.
func html(c *gin.Context, name string, title string, data gin.H) {
	if data == nil {
		data = gin.H{}
	}
	data["title"] = title
	host := c.GetHeader("X-Forwarded-Host")
	if host == "" {
		host = c.GetHeader("X-Real-IP")
	}
	if host == "" {
		var err error
		host, _, err = net.SplitHostPort(c.Request.Host)
		if err != nil {
			host = c.Request.Host
		}
	}
	data["host"] = host
	data["request_uri"] = c.Request.RequestURI
	data["base_path"] = c.GetString("base_path")

	logger.Info("Rendering template:", name, "for path:", c.Request.URL.Path)

	// Wrap HTML rendering to catch small responses and errors
	// Don't restore the original writer - let the wrapper stay until request completes
	originalWriter := c.Writer
	wrapper := &responseWriterWrapper{
		ResponseWriter: originalWriter,
		onWrite: func(p []byte) (int, error) {
			if len(p) < 100 && !strings.Contains(string(p), "<!DOCTYPE") {
				logger.Warning("Template", name, "rendered suspiciously small content:", len(p), "bytes, first 50 chars:", string(p[:min(len(p), 50)]))
			}
			return originalWriter.Write(p)
		},
	}
	c.Writer = wrapper

	// Render template with error handling
	defer func() {
		if r := recover(); r != nil {
			logger.Error("Panic during template rendering:", name, "error:", r)
		}
	}()

	c.HTML(http.StatusOK, name, getContext(data))

	// Flush to ensure gzip middleware completes compression
	wrapper.Flush()

	// Log response status after rendering
	if wrapper.Written() {
		size := wrapper.Size()
		contentEncoding := wrapper.Header().Get("Content-Encoding")
		contentType := wrapper.Header().Get("Content-Type")
		logger.Info("Template rendered successfully:", name, "status:", wrapper.Status(), "size:", size, "totalWritten:", wrapper.totalWritten, "Content-Encoding:", contentEncoding, "Content-Type:", contentType)
		if size < 100 && wrapper.totalWritten > 1000 {
			logger.Error("Template", name, "rendered suspiciously small content:", size, "bytes, but totalWritten:", wrapper.totalWritten, "- possible gzip compression issue or response interception")
			// Check if response was aborted
			if c.IsAborted() {
				logger.Error("Request was aborted for template:", name)
			}
			// Log all response headers for debugging
			logger.Error("Response headers for", name, ":", wrapper.Header())
		}
	} else {
		logger.Warning("Template rendered but no response written:", name)
	}
}

// getContext adds version and other context data to the provided gin.H.
func getContext(h gin.H) gin.H {
	a := gin.H{
		"cur_ver": config.GetVersion(),
	}
	for key, value := range h {
		a[key] = value
	}
	return a
}

// isAjax checks if the request is an AJAX request.
func isAjax(c *gin.Context) bool {
	return c.GetHeader("X-Requested-With") == "XMLHttpRequest"
}
