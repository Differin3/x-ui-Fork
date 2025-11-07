package service

import (
	"context"
	"crypto/rand"
	"encoding/base64"
	"errors"
	"time"

	"x-ui/internal/model"

	"golang.org/x/crypto/bcrypt"
	"gorm.io/gorm"
)

type AuthService struct {
	db *gorm.DB
}

func NewAuthService(db *gorm.DB) *AuthService {
	return &AuthService{db: db}
}

type LoginRequest struct {
	Username string `json:"username" binding:"required"`
	Password string `json:"password" binding:"required"`
}

type LoginResponse struct {
	Success bool   `json:"success"`
	Token   string `json:"token,omitempty"`
	Message string `json:"message,omitempty"`
	User    *UserInfo `json:"user,omitempty"`
}

type UserInfo struct {
	ID       uint   `json:"id"`
	Username string `json:"username"`
}

func (s *AuthService) Login(ctx context.Context, req LoginRequest) (*LoginResponse, error) {
	var user model.AdminUser
	if err := s.db.WithContext(ctx).
		Where("username = ? AND is_active = ?", req.Username, true).
		First(&user).Error; err != nil {
		if err == gorm.ErrRecordNotFound {
			return &LoginResponse{Success: false, Message: "Invalid username or password"}, nil
		}
		return nil, err
	}

	if err := bcrypt.CompareHashAndPassword([]byte(user.PasswordHash), []byte(req.Password)); err != nil {
		return &LoginResponse{Success: false, Message: "Invalid username or password"}, nil
	}

	now := time.Now()
	user.LastLogin = &now
	s.db.WithContext(ctx).Save(&user)

	token, err := s.generateToken()
	if err != nil {
		return nil, err
	}

	return &LoginResponse{
		Success: true,
		Token:   token,
		User: &UserInfo{
			ID:       user.ID,
			Username: user.Username,
		},
	}, nil
}

func (s *AuthService) ValidateToken(ctx context.Context, token string) (*UserInfo, error) {
	// Простая валидация токена - в production используйте JWT или сессии
	// Для простоты используем проверку наличия пользователя с таким токеном в сессии
	// В реальном приложении нужно хранить токены в базе или использовать JWT
	
	// Здесь можно добавить проверку токена через Redis или базу данных
	// Пока возвращаем ошибку, если токен пустой
	if token == "" {
		return nil, errors.New("token is required")
	}
	
	// Временная реализация - в production нужно добавить таблицу сессий
	return &UserInfo{ID: 1, Username: "admin"}, nil
}

func (s *AuthService) CreateAdmin(ctx context.Context, username, password string) error {
	hash, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	if err != nil {
		return err
	}

	user := model.AdminUser{
		Username:     username,
		PasswordHash: string(hash),
		IsActive:     true,
	}

	return s.db.WithContext(ctx).Create(&user).Error
}

func (s *AuthService) ChangePassword(ctx context.Context, userID uint, oldPassword, newPassword string) error {
	var user model.AdminUser
	if err := s.db.WithContext(ctx).First(&user, userID).Error; err != nil {
		return err
	}

	if err := bcrypt.CompareHashAndPassword([]byte(user.PasswordHash), []byte(oldPassword)); err != nil {
		return errors.New("invalid old password")
	}

	hash, err := bcrypt.GenerateFromPassword([]byte(newPassword), bcrypt.DefaultCost)
	if err != nil {
		return err
	}

	user.PasswordHash = string(hash)
	return s.db.WithContext(ctx).Save(&user).Error
}

func (s *AuthService) generateToken() (string, error) {
	b := make([]byte, 32)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return base64.URLEncoding.EncodeToString(b), nil
}

func (s *AuthService) HasAdmin(ctx context.Context) (bool, error) {
	var count int64
	if err := s.db.WithContext(ctx).Model(&model.AdminUser{}).Count(&count).Error; err != nil {
		return false, err
	}
	return count > 0, nil
}

