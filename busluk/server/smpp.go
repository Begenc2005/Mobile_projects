package main

// Минимальный SMPP 3.4 клиент (bind_transmitter, submit_sm, enquire_link)
// без внешних библиотек. Подходит для SMSC оператора (TMCell / Altyn Asyr).

import (
	"bufio"
	"encoding/binary"
	"errors"
	"fmt"
	"io"
	"log"
	"net"
	"sync"
	"time"
	"unicode/utf16"
)

const (
	cmdBindTX      = 0x00000002
	cmdSubmitSM    = 0x00000004
	cmdDeliverSM   = 0x00000005
	cmdUnbind      = 0x00000006
	cmdEnquireLink = 0x00000015
	cmdGenericNack = 0x80000000
	respBit        = 0x80000000
)

type SMPP struct {
	Addr, User, Pass, SystemType string
	Src                          string
	SrcTON, SrcNPI               byte

	mu      sync.Mutex
	conn    net.Conn
	seq     uint32
	pending map[uint32]chan uint32
	wmu     sync.Mutex
}

func (s *SMPP) Start() {
	s.pending = map[uint32]chan uint32{}
	go func() {
		for {
			if err := s.session(); err != nil {
				log.Printf("smpp: %v — переподключение через 10с", err)
			}
			time.Sleep(10 * time.Second)
		}
	}()
}

func cstr(b []byte, s string) []byte { return append(append(b, s...), 0) }

func (s *SMPP) nextSeq() uint32 {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.seq++
	if s.seq > 0x7FFFFFFF {
		s.seq = 1
	}
	return s.seq
}

func (s *SMPP) write(c net.Conn, cmd, status, seq uint32, body []byte) error {
	pdu := make([]byte, 16, 16+len(body))
	binary.BigEndian.PutUint32(pdu[0:], uint32(16+len(body)))
	binary.BigEndian.PutUint32(pdu[4:], cmd)
	binary.BigEndian.PutUint32(pdu[8:], status)
	binary.BigEndian.PutUint32(pdu[12:], seq)
	pdu = append(pdu, body...)
	s.wmu.Lock()
	defer s.wmu.Unlock()
	c.SetWriteDeadline(time.Now().Add(10 * time.Second))
	_, err := c.Write(pdu)
	return err
}

func readPDU(r *bufio.Reader) (cmd, status, seq uint32, body []byte, err error) {
	h := make([]byte, 16)
	if _, err = io.ReadFull(r, h); err != nil {
		return
	}
	n := binary.BigEndian.Uint32(h[0:])
	if n < 16 || n > 65536 {
		err = errors.New("bad pdu length")
		return
	}
	cmd = binary.BigEndian.Uint32(h[4:])
	status = binary.BigEndian.Uint32(h[8:])
	seq = binary.BigEndian.Uint32(h[12:])
	body = make([]byte, n-16)
	_, err = io.ReadFull(r, body)
	return
}

func (s *SMPP) session() error {
	c, err := net.DialTimeout("tcp", s.Addr, 10*time.Second)
	if err != nil {
		return err
	}
	defer c.Close()
	r := bufio.NewReader(c)

	var b []byte
	b = cstr(b, s.User)
	b = cstr(b, s.Pass)
	b = cstr(b, s.SystemType)
	b = append(b, 0x34, 0, 0) // interface_version, addr_ton, addr_npi
	b = cstr(b, "")
	if err := s.write(c, cmdBindTX, 0, s.nextSeq(), b); err != nil {
		return err
	}
	c.SetReadDeadline(time.Now().Add(15 * time.Second))
	cmd, st, _, _, err := readPDU(r)
	if err != nil {
		return err
	}
	if cmd != cmdBindTX|respBit || st != 0 {
		return fmt.Errorf("bind отклонён: cmd=%x status=%d", cmd, st)
	}
	log.Printf("smpp: подключено к %s", s.Addr)

	s.mu.Lock()
	s.conn = c
	s.mu.Unlock()
	defer func() {
		s.mu.Lock()
		s.conn = nil
		for k, ch := range s.pending {
			close(ch)
			delete(s.pending, k)
		}
		s.mu.Unlock()
	}()

	stop := make(chan struct{})
	defer close(stop)
	go func() { // keep-alive
		t := time.NewTicker(30 * time.Second)
		defer t.Stop()
		for {
			select {
			case <-stop:
				return
			case <-t.C:
				if s.write(c, cmdEnquireLink, 0, s.nextSeq(), nil) != nil {
					c.Close()
					return
				}
			}
		}
	}()

	for {
		c.SetReadDeadline(time.Now().Add(90 * time.Second))
		cmd, st, seq, _, err := readPDU(r)
		if err != nil {
			return err
		}
		switch {
		case cmd == cmdEnquireLink:
			s.write(c, cmdEnquireLink|respBit, 0, seq, nil)
		case cmd == cmdDeliverSM:
			s.write(c, cmdDeliverSM|respBit, 0, seq, []byte{0})
		case cmd == cmdUnbind:
			s.write(c, cmdUnbind|respBit, 0, seq, nil)
			return errors.New("SMSC закрыл сессию")
		case cmd == cmdSubmitSM|respBit || cmd == cmdGenericNack:
			s.mu.Lock()
			if ch, ok := s.pending[seq]; ok {
				ch <- st
				delete(s.pending, seq)
			}
			s.mu.Unlock()
		}
	}
}

// Send отправляет короткое SMS. ASCII -> GSM 7-bit (дешевле, 160 знаков), иначе UCS2.
func (s *SMPP) Send(to, text string) error {
	s.mu.Lock()
	c := s.conn
	s.mu.Unlock()
	if c == nil {
		return errors.New("smpp не подключён")
	}
	dc, msg := byte(0), []byte(text)
	for _, r := range text {
		if r > 127 {
			dc = 8
			u := utf16.Encode([]rune(text))
			msg = make([]byte, len(u)*2)
			for i, v := range u {
				binary.BigEndian.PutUint16(msg[i*2:], v)
			}
			break
		}
	}
	if len(msg) > 254 {
		return errors.New("сообщение слишком длинное")
	}
	var b []byte
	b = cstr(b, "")                // service_type
	b = append(b, s.SrcTON, s.SrcNPI)
	b = cstr(b, s.Src)
	b = append(b, 1, 1) // dest TON international, NPI ISDN
	b = cstr(b, to)
	b = append(b, 0, 0, 0) // esm_class, protocol_id, priority
	b = cstr(b, "")        // schedule
	b = cstr(b, "")        // validity
	b = append(b, 0, 0, dc, 0, byte(len(msg)))
	b = append(b, msg...)

	seq := s.nextSeq()
	ch := make(chan uint32, 1)
	s.mu.Lock()
	s.pending[seq] = ch
	s.mu.Unlock()
	if err := s.write(c, cmdSubmitSM, 0, seq, b); err != nil {
		return err
	}
	select {
	case st, ok := <-ch:
		if !ok {
			return errors.New("соединение прервано")
		}
		if st != 0 {
			return fmt.Errorf("SMSC ошибка %d", st)
		}
		return nil
	case <-time.After(15 * time.Second):
		s.mu.Lock()
		delete(s.pending, seq)
		s.mu.Unlock()
		return errors.New("таймаут SMSC")
	}
}
