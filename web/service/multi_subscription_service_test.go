package service

import (
	"fmt"
	"path/filepath"
	"testing"

	"github.com/mhsanaei/3x-ui/v2/database"
	"github.com/mhsanaei/3x-ui/v2/database/model"
)

func setupMultiSubTestDB(t *testing.T) {
	t.Helper()
	_ = database.CloseDB()
	tdb := filepath.Join(t.TempDir(), "multi.db")
	if err := database.InitDB(tdb); err != nil {
		t.Fatalf("failed to init test db: %v", err)
	}
	t.Cleanup(func() { _ = database.CloseDB() })
}

func TestMultiSubscriptionServiceValidation(t *testing.T) {
	setupMultiSubTestDB(t)
	nodeSvc := &NodeService{}
	multiSvc := &MultiSubscriptionService{nodeService: *nodeSvc}

	node := &model.Node{Name: "node-valid", Host: "127.0.0.1", Port: 5050, Enable: true}
	if err := nodeSvc.AddNode(node); err != nil {
		t.Fatalf("failed to add node: %v", err)
	}

	ms := &model.MultiSubscription{Name: "combo", NodeIds: fmt.Sprintf("[%d]", node.Id)}
	if err := multiSvc.AddMultiSubscription(ms); err != nil {
		t.Fatalf("AddMultiSubscription failed: %v", err)
	}
	if ms.SubId == "" {
		t.Fatalf("expected generated SubId")
	}

	// Duplicate subId
	dup := &model.MultiSubscription{Name: "dup", SubId: ms.SubId}
	if err := multiSvc.AddMultiSubscription(dup); err == nil {
		t.Fatalf("expected error on duplicate subId")
	}

	// Invalid node ids JSON
	invalid := &model.MultiSubscription{Name: "bad", NodeIds: "not-json"}
	if err := multiSvc.AddMultiSubscription(invalid); err == nil {
		t.Fatalf("expected error on invalid node ids json")
	}

	// Validation should fail when node disabled
	node.Enable = false
	if err := nodeSvc.UpdateNode(node); err != nil {
		t.Fatalf("failed to update node: %v", err)
	}
	if err := multiSvc.ValidateMultiSubscription(ms); err == nil {
		t.Fatalf("expected validation error for disabled node")
	}
}

func TestMultiSubscriptionServiceCRUD(t *testing.T) {
	setupMultiSubTestDB(t)
	nodeSvc := &NodeService{}
	multiSvc := &MultiSubscriptionService{nodeService: *nodeSvc}

	node1 := &model.Node{Name: "node-1", Host: "n1", Port: 5050, Enable: true}
	node2 := &model.Node{Name: "node-2", Host: "n2", Port: 2054, Enable: true}
	if err := nodeSvc.AddNode(node1); err != nil {
		t.Fatalf("failed to add node1: %v", err)
	}
	if err := nodeSvc.AddNode(node2); err != nil {
		t.Fatalf("failed to add node2: %v", err)
	}

	ms := &model.MultiSubscription{Name: "primary", NodeIds: fmt.Sprintf("[%d]", node1.Id)}
	if err := multiSvc.AddMultiSubscription(ms); err != nil {
		t.Fatalf("AddMultiSubscription failed: %v", err)
	}

	fetched, err := multiSvc.GetMultiSubscription(ms.Id)
	if err != nil {
		t.Fatalf("GetMultiSubscription failed: %v", err)
	}
	if fetched.Name != "primary" {
		t.Fatalf("expected name primary, got %s", fetched.Name)
	}

	fetched.Name = "updated"
	fetched.NodeIds = fmt.Sprintf("[%d,%d]", node1.Id, node2.Id)
	if err := multiSvc.UpdateMultiSubscription(fetched); err != nil {
		t.Fatalf("UpdateMultiSubscription failed: %v", err)
	}

	bySubId, err := multiSvc.GetMultiSubscriptionBySubId(fetched.SubId)
	if err != nil {
		t.Fatalf("GetMultiSubscriptionBySubId failed: %v", err)
	}
	if bySubId.Id != fetched.Id {
		t.Fatalf("expected ids to match")
	}

	ids, err := multiSvc.GetNodeIds(bySubId)
	if err != nil {
		t.Fatalf("GetNodeIds failed: %v", err)
	}
	if len(ids) != 2 {
		t.Fatalf("expected 2 node ids, got %d", len(ids))
	}

	nodes, err := multiSvc.GetNodes(bySubId)
	if err != nil {
		t.Fatalf("GetNodes failed: %v", err)
	}
	if len(nodes) != 2 {
		t.Fatalf("expected 2 nodes returned, got %d", len(nodes))
	}

	all, err := multiSvc.GetAllMultiSubscriptions()
	if err != nil {
		t.Fatalf("GetAllMultiSubscriptions failed: %v", err)
	}
	if len(all) != 1 {
		t.Fatalf("expected 1 multi-subscription, got %d", len(all))
	}

	enabled, err := multiSvc.GetEnabledMultiSubscriptions()
	if err != nil {
		t.Fatalf("GetEnabledMultiSubscriptions failed: %v", err)
	}
	if len(enabled) != 1 {
		t.Fatalf("expected enabled multi-subscriptions, got %d", len(enabled))
	}

	if err := multiSvc.DeleteMultiSubscription(ms.Id); err != nil {
		t.Fatalf("DeleteMultiSubscription failed: %v", err)
	}

	if _, err := multiSvc.GetMultiSubscription(ms.Id); err == nil {
		t.Fatalf("expected error when fetching deleted multi-subscription")
	}
}
