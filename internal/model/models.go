package model

import "time"

type NodeStatus string

const (
	NodeStatusOnline   NodeStatus = "online"
	NodeStatusOffline  NodeStatus = "offline"
	NodeStatusSyncing  NodeStatus = "syncing"
	NodeStatusDegraded NodeStatus = "degraded"
)

type Node struct {
	ID          string     `gorm:"primaryKey;size:50"`
	Name        string     `gorm:"size:255;not null"`
	MasterURL   string     `gorm:"size:500;not null"`
	SecretKey   string     `gorm:"size:255;not null"`
	Status      NodeStatus `gorm:"type:varchar(20);default:'offline'"`
	IPAddress   string     `gorm:"size:45"`
	Hostname    string     `gorm:"size:255"`
	Location    string     `gorm:"size:100"`
	XrayVersion string     `gorm:"size:50"`
	ListenAddr  string     `gorm:"size:100"`
	LastSeen    time.Time
	CreatedAt   time.Time
	UpdatedAt   time.Time

	Groups []NodeGroup `gorm:"many2many:group_nodes"`
}

func (Node) TableName() string {
	return "nodes"
}

type NodeGroup struct {
	ID          uint   `gorm:"primaryKey"`
	Name        string `gorm:"size:255;not null"`
	Description string `gorm:"type:text"`
	IsActive    bool   `gorm:"default:true"`
	CreatedAt   time.Time
	UpdatedAt   time.Time

	Nodes []Node `gorm:"many2many:group_nodes"`
}

func (NodeGroup) TableName() string {
	return "node_groups"
}

type GroupNode struct {
	ID       uint `gorm:"primaryKey"`
	GroupID  uint
	NodeID   string `gorm:"size:50"`
	Weight   int    `gorm:"default:1"`
	IsActive bool   `gorm:"default:true"`

	CreatedAt time.Time
	UpdatedAt time.Time
}

func (GroupNode) TableName() string {
	return "group_nodes"
}

type CentralInbound struct {
	ID             uint   `gorm:"primaryKey"`
	Name           string `gorm:"size:255;not null"`
	Protocol       string `gorm:"size:20;not null"`
	Port           int    `gorm:"not null"`
	Settings       []byte `gorm:"type:json"`
	StreamSettings []byte `gorm:"type:json"`
	Sniffing       []byte `gorm:"type:json"`
	ClientStats    bool   `gorm:"default:true"`
	IsActive       bool   `gorm:"default:true"`
	CreatedAt      time.Time
	UpdatedAt      time.Time
}

func (CentralInbound) TableName() string {
	return "central_inbounds"
}

type Client struct {
	ID             uint   `gorm:"primaryKey"`
	Email          string `gorm:"size:255;uniqueIndex;not null"`
	UUID           string `gorm:"size:36;not null"`
	SubscriptionID string `gorm:"size:100"`
	TrafficLimit   int64  `gorm:"default:0"`
	UsedTraffic    int64  `gorm:"default:0"`
	ExpireAt       *time.Time
	IsActive       bool `gorm:"default:true"`
	CreatedAt      time.Time
	UpdatedAt      time.Time

	Subscriptions []UserSubscription `gorm:"foreignKey:UserID;references:ID"`
}

func (Client) TableName() string {
	return "clients"
}

type UserSubscription struct {
	ID           uint `gorm:"primaryKey"`
	UserID       uint `gorm:"index"`
	GroupID      uint `gorm:"index"`
	ExpireAt     *time.Time
	TrafficLimit int64 `gorm:"default:0"`
	UsedTraffic  int64 `gorm:"default:0"`
	IsActive     bool  `gorm:"default:true"`
	CreatedAt    time.Time
	UpdatedAt    time.Time
}

func (UserSubscription) TableName() string {
	return "user_subscriptions"
}

type ClientNodeStat struct {
	ID        uint   `gorm:"primaryKey"`
	ClientID  uint   `gorm:"index"`
	NodeID    string `gorm:"size:50"`
	Upload    int64  `gorm:"default:0"`
	Download  int64  `gorm:"default:0"`
	LastUsed  *time.Time
	CreatedAt time.Time
	UpdatedAt time.Time
}

func (ClientNodeStat) TableName() string {
	return "client_node_stats"
}

type DomainCertificate struct {
	ID          uint   `gorm:"primaryKey"`
	Domain      string `gorm:"size:255;uniqueIndex;not null"`
	CertFile    string `gorm:"size:500"`
	KeyFile     string `gorm:"size:500"`
	CertContent []byte `gorm:"type:text"`
	KeyContent  []byte `gorm:"type:text"`
	Issuer      string `gorm:"size:255"`
	ExpiresAt   *time.Time
	AutoRenew   bool `gorm:"default:false"`
	LastChecked *time.Time
	CreatedAt   time.Time
	UpdatedAt   time.Time
}

func (DomainCertificate) TableName() string {
	return "domain_certificates"
}

type AdminUser struct {
	ID           uint   `gorm:"primaryKey"`
	Username     string `gorm:"size:100;uniqueIndex;not null"`
	PasswordHash string `gorm:"size:255;not null"`
	IsActive     bool   `gorm:"default:true"`
	LastLogin    *time.Time
	CreatedAt    time.Time
	UpdatedAt    time.Time
}

func (AdminUser) TableName() string {
	return "admin_users"
}
