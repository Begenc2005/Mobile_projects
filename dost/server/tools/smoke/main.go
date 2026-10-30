// Smoke test: two users register, chat, send text + image + voice, reactions, read receipts, sync.
// Usage: go run ./tools/smoke http://localhost:8080   (server must run with DEV_MODE=1)
package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"mime/multipart"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/coder/websocket"
)

var base = "http://localhost:8080"

func must(err error) {
	if err != nil {
		fmt.Println("FAIL:", err)
		os.Exit(1)
	}
}

func call(method, path, token string, body any, out any) int {
	var rd io.Reader
	if body != nil {
		b, _ := json.Marshal(body)
		rd = bytes.NewReader(b)
	}
	req, _ := http.NewRequest(method, base+path, rd)
	req.Header.Set("Content-Type", "application/json")
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	resp, err := http.DefaultClient.Do(req) // Go client transparently un-gzips
	must(err)
	defer resp.Body.Close()
	b, _ := io.ReadAll(resp.Body)
	if out != nil {
		_ = json.Unmarshal(b, out)
	}
	if resp.StatusCode >= 300 {
		fmt.Printf("  %s %s -> %d %s\n", method, path, resp.StatusCode, b)
	}
	return resp.StatusCode
}

type user struct {
	token string
	id    int64
	ws    *websocket.Conn
	in    chan map[string]any
}

func register(phone, name string) *user {
	var c struct {
		DevCode string `json:"dev_code"`
	}
	if call("POST", "/api/auth/code", "", map[string]string{"phone": phone}, &c) != 200 {
		must(fmt.Errorf("code"))
	}
	var v struct {
		Token string `json:"token"`
		User  struct{ ID int64 } `json:"user"`
	}
	call("POST", "/api/auth/verify", "", map[string]string{"phone": phone, "code": c.DevCode, "device": "smoke"}, &v)
	if v.Token == "" {
		must(fmt.Errorf("verify failed"))
	}
	call("PUT", "/api/me", v.Token, map[string]string{"name": name}, nil)
	u := &user{token: v.Token, id: v.User.ID, in: make(chan map[string]any, 100)}
	ws, _, err := websocket.Dial(context.Background(), strings.Replace(base, "http", "ws", 1)+"/ws?t="+u.token,
		&websocket.DialOptions{CompressionMode: websocket.CompressionContextTakeover})
	must(err)
	u.ws = ws
	go func() {
		for {
			_, b, err := ws.Read(context.Background())
			if err != nil {
				return
			}
			var m map[string]any
			_ = json.Unmarshal(b, &m)
			u.in <- m
		}
	}()
	return u
}

func (u *user) send(m map[string]any) {
	b, _ := json.Marshal(m)
	must(u.ws.Write(context.Background(), websocket.MessageText, b))
}

func (u *user) wait(t string) map[string]any {
	deadline := time.After(5 * time.Second)
	for {
		select {
		case m := <-u.in:
			if m["t"] == t {
				return m
			}
		case <-deadline:
			must(fmt.Errorf("timeout waiting for %q", t))
		}
	}
}

func upload(token, kind, mime string, data []byte) string {
	var buf bytes.Buffer
	mw := multipart.NewWriter(&buf)
	_ = mw.WriteField("mime", mime)
	_ = mw.WriteField("w", "10")
	_ = mw.WriteField("h", "10")
	fw, _ := mw.CreateFormFile("file", "f")
	_, _ = fw.Write(data)
	mw.Close()
	req, _ := http.NewRequest("POST", base+"/api/media?kind="+kind, &buf)
	req.Header.Set("Content-Type", mw.FormDataContentType())
	req.Header.Set("Authorization", "Bearer "+token)
	resp, err := http.DefaultClient.Do(req)
	must(err)
	defer resp.Body.Close()
	var info struct{ ID string }
	b, _ := io.ReadAll(resp.Body)
	_ = json.Unmarshal(b, &info)
	if info.ID == "" {
		must(fmt.Errorf("upload failed: %s", b))
	}
	return info.ID
}

func main() {
	if len(os.Args) > 1 {
		base = os.Args[1]
	}
	a := register("+993 65 111111", "Aman")
	b := register("865222222", "Bahar")
	a.wait("hello")
	b.wait("hello")
	fmt.Println("✓ register + login + websocket")

	var found []map[string]any
	call("POST", "/api/users/lookup", a.token, map[string]any{"phones": []string{"+99365222222", "+99360000000"}}, &found)
	if len(found) != 1 {
		must(fmt.Errorf("lookup expected 1, got %d", len(found)))
	}
	fmt.Println("✓ contact lookup")

	var chat struct{ ID int64 }
	call("POST", "/api/chats/direct", a.token, map[string]any{"user": b.id}, &chat)
	var chat2 struct{ ID int64 }
	call("POST", "/api/chats/direct", b.token, map[string]any{"user": a.id}, &chat2)
	if chat.ID == 0 || chat.ID != chat2.ID {
		must(fmt.Errorf("direct chat mismatch %d %d", chat.ID, chat2.ID))
	}
	fmt.Println("✓ direct chat (same for both sides)")

	a.send(map[string]any{"t": "send", "cid": "c1", "chat": chat.ID, "k": 1, "tx": "Salam, Bahar! Нахалсын?"})
	ack := a.wait("ack")
	got := b.wait("msg")
	msgID := int64(got["msg"].(map[string]any)["id"].(float64))
	if ack["msg"].(map[string]any)["id"].(float64) != float64(msgID) {
		must(fmt.Errorf("ack/msg id mismatch"))
	}
	// resend same cid (flaky network) must not duplicate
	a.send(map[string]any{"t": "send", "cid": "c1", "chat": chat.ID, "k": 1, "tx": "Salam, Bahar! Нахалсын?"})
	a.wait("ack")
	fmt.Println("✓ text message delivered, idempotent resend")

	b.send(map[string]any{"t": "typing", "chat": chat.ID})
	a.wait("typing")
	b.send(map[string]any{"t": "read", "chat": chat.ID, "id": msgID})
	a.wait("read")
	b.send(map[string]any{"t": "react", "id": msgID, "e": "❤️"})
	a.wait("rx")
	fmt.Println("✓ typing, read receipt, reaction")

	jpeg := append([]byte{0xFF, 0xD8, 0xFF, 0xE0}, bytes.Repeat([]byte{1}, 2000)...)
	img := upload(a.token, "image", "image/jpeg", jpeg)
	a.send(map[string]any{"t": "send", "cid": "c2", "chat": chat.ID, "k": 2, "m": img, "tx": "Surat"})
	m2 := b.wait("msg")["msg"].(map[string]any)
	if m2["m"].(map[string]any)["id"] != img {
		must(fmt.Errorf("image not attached"))
	}
	voice := upload(b.token, "voice", "audio/mp4", bytes.Repeat([]byte{7}, 3000))
	b.send(map[string]any{"t": "send", "cid": "v1", "chat": chat.ID, "k": 3, "m": voice})
	a.wait("msg")
	// media download with Range
	req, _ := http.NewRequest("GET", base+"/media/"+voice+"?t="+a.token, nil)
	req.Header.Set("Range", "bytes=0-99")
	resp, err := http.DefaultClient.Do(req)
	must(err)
	if resp.StatusCode != 206 {
		must(fmt.Errorf("range expected 206, got %d", resp.StatusCode))
	}
	resp.Body.Close()
	fmt.Println("✓ image + voice upload, delivery, ranged download")

	var g struct{ ID int64 }
	call("POST", "/api/chats/group", a.token, map[string]any{"title": "Maşgala", "members": []int64{b.id}}, &g)
	b.wait("chat")
	fmt.Println("✓ group created, member notified")

	var chats []map[string]any
	call("GET", "/api/chats", b.token, nil, &chats)
	if len(chats) != 2 {
		must(fmt.Errorf("expected 2 chats, got %d", len(chats)))
	}
	var hist []map[string]any
	call("GET", fmt.Sprintf("/api/chats/%d/messages", chat.ID), b.token, nil, &hist)
	if len(hist) != 3 {
		must(fmt.Errorf("expected 3 messages, got %d", len(hist)))
	}
	var sync struct {
		Msgs []map[string]any `json:"msgs"`
	}
	call("GET", "/api/sync?after=0", b.token, nil, &sync)
	if len(sync.Msgs) != 4 {
		must(fmt.Errorf("sync expected 4, got %d", len(sync.Msgs)))
	}
	fmt.Println("✓ chat list, history, offline sync")

	a.send(map[string]any{"t": "edit", "id": msgID, "tx": "Salam! (edited)"})
	b.wait("upd")
	a.send(map[string]any{"t": "del", "id": msgID})
	b.wait("upd")
	fmt.Println("✓ edit + delete")

	if call("GET", "/api/chats", "bad-token", nil, nil) != 401 {
		must(fmt.Errorf("auth not enforced"))
	}
	fmt.Println("✓ auth enforced\nALL OK")
}
