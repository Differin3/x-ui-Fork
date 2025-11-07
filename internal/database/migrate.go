package database

import (
	"x-ui/internal/model"

	"gorm.io/gorm"
)

func AutoMigrate(db *gorm.DB) error {
	return db.AutoMigrate(
		&model.Node{},
		&model.NodeGroup{},
		&model.GroupNode{},
		&model.CentralInbound{},
		&model.Client{},
		&model.UserSubscription{},
		&model.ClientNodeStat{},
		&model.DomainCertificate{},
		&model.AdminUser{},
	)
}
