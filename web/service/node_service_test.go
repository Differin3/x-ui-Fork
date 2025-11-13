package service

import (
	"path/filepath"
	"testing"

	"github.com/mhsanaei/3x-ui/v2/database"
	"github.com/mhsanaei/3x-ui/v2/database/model"
)

func setupServiceTestDB(t *testing.T) {
	t.Helper()
	_ = database.CloseDB()
	tdb := filepath.Join(t.TempDir(), "test.db")
	if err := database.InitDB(tdb); err != nil {
		t.Fatalf("failed to init test db: %v", err)
	}
	t.Cleanup(func() { _ = database.CloseDB() })
}

func TestNodeServiceValidation(t *testing.T) {
	setupServiceTestDB(t)
	svc := &NodeService{}

	if err := svc.AddNode(&model.Node{}); err == nil {
		t.Fatalf("expected error when adding empty node")
	}

	node := &model.Node{Name: "valid", Host: "127.0.0.1", Port: 0}
	if err := svc.AddNode(node); err == nil {
		t.Fatalf("expected error when port <= 0")
	}
}

func TestNodeServiceCRUD(t *testing.T) {
	setupServiceTestDB(t)
	svc := &NodeService{}

	node := &model.Node{Name: "node-1", Host: "127.0.0.1", Port: 5050, Enable: true}
	if err := svc.AddNode(node); err != nil {
		t.Fatalf("AddNode failed: %v", err)
	}
	if node.Id == 0 {
		t.Fatalf("expected node to receive ID")
	}
	if node.Protocol != "https" {
		t.Fatalf("expected default protocol https, got %s", node.Protocol)
	}
	if node.Status == "" {
		t.Fatalf("expected default status to be set")
	}

	fetched, err := svc.GetNode(node.Id)
	if err != nil {
		t.Fatalf("GetNode failed: %v", err)
	}
	if fetched.Name != node.Name {
		t.Fatalf("expected name %s, got %s", node.Name, fetched.Name)
	}

	node.Name = "node-1-updated"
	node.Enable = false
	if err := svc.UpdateNode(node); err != nil {
		t.Fatalf("UpdateNode failed: %v", err)
	}

	nodes, err := svc.GetAllNodes()
	if err != nil {
		t.Fatalf("GetAllNodes failed: %v", err)
	}
	if len(nodes) != 1 {
		t.Fatalf("expected 1 node, got %d", len(nodes))
	}

	enabled, err := svc.GetEnabledNodes()
	if err != nil {
		t.Fatalf("GetEnabledNodes failed: %v", err)
	}
	if len(enabled) != 0 {
		t.Fatalf("expected 0 enabled nodes, got %d", len(enabled))
	}

	geoNode := &model.Node{Name: "geo", Host: "geo.local", Port: 2054, Enable: true, Latitude: 10.5, Longitude: 20.5}
	if err := svc.AddNode(geoNode); err != nil {
		t.Fatalf("AddNode (geo) failed: %v", err)
	}

	mapNodes, err := svc.GetNodesWithCoordinates()
	if err != nil {
		t.Fatalf("GetNodesWithCoordinates failed: %v", err)
	}
	if len(mapNodes) != 1 || mapNodes[0].Id != geoNode.Id {
		t.Fatalf("expected coordinates node to be returned")
	}

	if err := svc.DeleteNode(node.Id); err != nil {
		t.Fatalf("DeleteNode failed: %v", err)
	}

	if _, err := svc.GetNode(node.Id); err == nil {
		t.Fatalf("expected error when getting deleted node")
	}
}
