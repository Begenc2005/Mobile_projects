package main

// Онлайн-оплата через платёжный шлюз банка (REST API типа RBS/BPC:
// register.do + getOrderStatusExtended.do). Такой интерфейс у шлюзов
// туркменских банков; точный адрес и логин выдаёт банк по договору эквайринга.

import (
	"encoding/json"
	"fmt"
	"html"
	"log"
	"net/http"
	"net/url"
	"strconv"
	"time"
)

type PayCfg struct {
	URL, User, Pass, Currency string
	Mult                      int64 // манат -> минимальные единицы (тенге)
	Mock                      bool  // тестовый режим без банка
}

var bankClient = &http.Client{Timeout: 20 * time.Second}

func bankCall(method string, params url.Values) (map[string]any, error) {
	params.Set("userName", cfg.Pay.User)
	params.Set("password", cfg.Pay.Pass)
	resp, err := bankClient.PostForm(cfg.Pay.URL+"/"+method, params)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	var out map[string]any
	if err := json.NewDecoder(resp.Body).Decode(&out); err != nil {
		return nil, err
	}
	if ec := fmt.Sprint(out["errorCode"]); ec != "<nil>" && ec != "0" && ec != "" {
		return out, fmt.Errorf("банк: %v %v", ec, out["errorMessage"])
	}
	return out, nil
}

func svcPrice(svc string) int64 {
	switch svc {
	case "bump":
		return cfg.Prices.Bump
	case "vip7":
		return cfg.Prices.Vip7
	case "vip30":
		return cfg.Prices.Vip30
	}
	return 0
}

// POST /v1/pay {ad, svc} -> {url}: приложение открывает url в браузере.
func hPay(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Ad  int64
		Svc string
	}
	if !readBody(r, &in) || svcPrice(in.Svc) == 0 {
		fail(w, r, 400, "bad")
		return
	}
	u := me(r)
	var st int
	if db.QueryRow(`SELECT status FROM ads WHERE id=$1 AND user_id=$2`, in.Ad, u.ID).Scan(&st) != nil || st == 2 || st == 4 {
		fail(w, r, 404, "nf")
		return
	}
	amount := svcPrice(in.Svc) * cfg.Pay.Mult
	var pid int64
	if err := db.QueryRow(`INSERT INTO payments(order_no,user_id,ad_id,svc,amount) VALUES('tmp'||nextval('payments_id_seq'),$1,$2,$3,$4)
		RETURNING id`, u.ID, in.Ad, in.Svc, amount).Scan(&pid); err != nil {
		fail(w, r, 500, "db")
		return
	}
	orderNo := fmt.Sprintf("BL%08d", pid)
	db.Exec(`UPDATE payments SET order_no=$1 WHERE id=$2`, orderNo, pid)
	ret := cfg.PublicURL + "/pay/ret?o=" + orderNo

	if cfg.Pay.Mock || cfg.Pay.URL == "" {
		writeJSON(w, r, 200, map[string]string{"url": cfg.PublicURL + "/pay/mock?o=" + orderNo})
		return
	}
	out, err := bankCall("register.do", url.Values{
		"orderNumber": {orderNo}, "amount": {strconv.FormatInt(amount, 10)}, "currency": {cfg.Pay.Currency},
		"returnUrl": {ret}, "failUrl": {ret}, "language": {"ru"},
		"description": {fmt.Sprintf("Busluk %s #%d", in.Svc, in.Ad)},
	})
	if err != nil {
		log.Print("pay register: ", err)
		fail(w, r, 502, "bank")
		return
	}
	bankID, _ := out["orderId"].(string)
	formURL, _ := out["formUrl"].(string)
	db.Exec(`UPDATE payments SET bank_id=$1 WHERE id=$2`, bankID, pid)
	writeJSON(w, r, 200, map[string]string{"url": formURL})
}

// checkPayment спрашивает банк и, если оплачено, применяет услугу. Идемпотентно.
func checkPayment(orderNo string) (paid bool) {
	var pid, adID int64
	var bankID, svc string
	var st int
	if db.QueryRow(`SELECT id,bank_id,ad_id,svc,status FROM payments WHERE order_no=$1`, orderNo).
		Scan(&pid, &bankID, &adID, &svc, &st) != nil {
		return false
	}
	if st == 1 {
		return true
	}
	if !cfg.Pay.Mock && cfg.Pay.URL != "" {
		if bankID == "" {
			return false
		}
		out, err := bankCall("getOrderStatusExtended.do", url.Values{"orderId": {bankID}})
		if err != nil {
			return false
		}
		os := fmt.Sprint(out["orderStatus"])
		if os == "<nil>" {
			os = fmt.Sprint(out["OrderStatus"])
		}
		switch os {
		case "2": // оплачен
		case "3", "6": // отменён / отклонён
			db.Exec(`UPDATE payments SET status=2 WHERE id=$1 AND status=0`, pid)
			return false
		default:
			return false
		}
	}
	return applyPaid(pid, adID, svc)
}

func applyPaid(pid, adID int64, svc string) bool {
	tx, err := db.Begin()
	if err != nil {
		return false
	}
	defer tx.Rollback()
	res, err := tx.Exec(`UPDATE payments SET status=1, paid_at=now() WHERE id=$1 AND status=0`, pid)
	if err != nil {
		return false
	}
	if n, _ := res.RowsAffected(); n == 0 {
		return true // уже применено
	}
	days := map[string]int{"vip7": 7, "vip30": 30}[svc]
	// любая услуга поднимает объявление наверх и возвращает истёкшее в ленту
	q := `UPDATE ads SET bumped_at=now(), status=CASE WHEN status=3 THEN 0 ELSE status END`
	if days > 0 {
		q += `, vip_until = greatest(coalesce(vip_until, now()), now()) + make_interval(days => ` + strconv.Itoa(days) + `)`
	}
	if _, err := tx.Exec(q+` WHERE id=$1`, adID); err != nil {
		return false
	}
	return tx.Commit() == nil
}

func checkPendingPayments() {
	rows, err := db.Query(`SELECT order_no FROM payments WHERE status=0 AND created_at > now()-interval '2 hours'`)
	if err != nil {
		return
	}
	var list []string
	for rows.Next() {
		var o string
		rows.Scan(&o)
		list = append(list, o)
	}
	rows.Close()
	for _, o := range list {
		checkPayment(o)
	}
}

const payPage = `<!doctype html><meta charset=utf-8><meta name=viewport content="width=device-width">
<title>Buşluk</title><body style="font:18px sans-serif;text-align:center;padding:40px 16px">
<div style="font-size:56px">%s</div><h2>%s</h2><p>%s</p>
<p><a href="busluk://paid" style="display:inline-block;padding:14px 28px;background:#0a7d4f;color:#fff;border-radius:10px;text-decoration:none">Buşluk</a></p>`

func hPayReturn(w http.ResponseWriter, r *http.Request) {
	o := r.URL.Query().Get("o")
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	if checkPayment(o) {
		fmt.Fprintf(w, payPage, "✅", "Töleg kabul edildi", "Оплата принята. "+html.EscapeString(o))
		return
	}
	fmt.Fprintf(w, payPage, "⚠️", "Töleg tamamlanmady", "Оплата не завершена. Если деньги списаны — услуга включится автоматически в течение нескольких минут.")
}

// Тестовый «банк»: работает только при PAY_MOCK=1 или пустом PAY_URL.
func hPayMock(w http.ResponseWriter, r *http.Request) {
	if !cfg.Pay.Mock && cfg.Pay.URL != "" {
		http.NotFound(w, r)
		return
	}
	o := r.URL.Query().Get("o")
	if r.URL.Query().Get("ok") == "1" {
		var pid, adID int64
		var svc string
		if db.QueryRow(`SELECT id,ad_id,svc FROM payments WHERE order_no=$1`, o).Scan(&pid, &adID, &svc) == nil {
			applyPaid(pid, adID, svc)
		}
		http.Redirect(w, r, "/pay/ret?o="+url.QueryEscape(o), http.StatusFound)
		return
	}
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	fmt.Fprintf(w, payPage, "🧪", "Test töleg / Тестовая оплата", html.EscapeString(o)+
		`</p><p><a href="?o=`+url.QueryEscape(o)+`&ok=1">Оплатить (тест)</a>`)
}
