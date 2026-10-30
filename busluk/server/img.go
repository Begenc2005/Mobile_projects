package main

import (
	"bytes"
	"image"
	"image/color"
	"image/jpeg"
	_ "image/png"
	"io"
	"net/http"
	"os"
	"strconv"
	"time"
)

// Фото: клиент шлёт JPEG телом запроса (без multipart — меньше кода и байт).
// Сервер перекодирует (EXIF с GPS удаляется) в 1080px и миниатюру 320px.
// Миниатюра ~12–20 КБ — именно её грузит лента.

func hPhoto(w http.ResponseWriter, r *http.Request) {
	u := me(r)
	if !lim.allow("up:"+strconv.FormatInt(u.ID, 10), 120, time.Hour) {
		fail(w, r, 429, "wait")
		return
	}
	data, err := io.ReadAll(http.MaxBytesReader(w, r.Body, 8<<20))
	if err != nil {
		fail(w, r, 413, "big")
		return
	}
	src, _, err := image.Decode(bytes.NewReader(data))
	if err != nil {
		fail(w, r, 400, "img")
		return
	}
	name := strconv.FormatInt(u.ID, 10) + "_" + randHex(8)
	base := cfg.DataDir + "/img/" + name
	if saveJPEG(base+".jpg", fit(src, 1080), 72) != nil || saveJPEG(base+"_t.jpg", fit(src, 320), 60) != nil {
		fail(w, r, 500, "io")
		return
	}
	writeJSON(w, r, 200, map[string]string{"f": name})
}

func removePhoto(name string) {
	if photoRe.MatchString(name) {
		os.Remove(cfg.DataDir + "/img/" + name + ".jpg")
		os.Remove(cfg.DataDir + "/img/" + name + "_t.jpg")
	}
}

func saveJPEG(path string, img image.Image, q int) error {
	f, err := os.Create(path)
	if err != nil {
		return err
	}
	defer f.Close()
	return jpeg.Encode(f, img, &jpeg.Options{Quality: q})
}

// fit уменьшает изображение по длинной стороне до max (усреднение по площади — без «лесенки»).
func fit(src image.Image, max int) image.Image {
	b := src.Bounds()
	sw, sh := b.Dx(), b.Dy()
	dw, dh := sw, sh
	if sw >= sh && sw > max {
		dw, dh = max, sh*max/sw
	} else if sh > sw && sh > max {
		dw, dh = sw*max/sh, max
	}
	if dw < 1 {
		dw = 1
	}
	if dh < 1 {
		dh = 1
	}
	dst := image.NewRGBA(image.Rect(0, 0, dw, dh))
	if dw == sw && dh == sh {
		for y := 0; y < sh; y++ {
			for x := 0; x < sw; x++ {
				dst.Set(x, y, src.At(b.Min.X+x, b.Min.Y+y))
			}
		}
		return dst
	}
	for y := 0; y < dh; y++ {
		y0, y1 := y*sh/dh, (y+1)*sh/dh
		if y1 <= y0 {
			y1 = y0 + 1
		}
		for x := 0; x < dw; x++ {
			x0, x1 := x*sw/dw, (x+1)*sw/dw
			if x1 <= x0 {
				x1 = x0 + 1
			}
			// для скорости берём не больше 4×4 точек на пиксель
			sx, sy := (x1-x0+3)/4, (y1-y0+3)/4
			var rr, gg, bb, n uint32
			for yy := y0; yy < y1; yy += sy {
				for xx := x0; xx < x1; xx += sx {
					cr, cg, cb, _ := src.At(b.Min.X+xx, b.Min.Y+yy).RGBA()
					rr, gg, bb, n = rr+cr, gg+cg, bb+cb, n+1
				}
			}
			dst.SetRGBA(x, y, color.RGBA{uint8(rr / n >> 8), uint8(gg / n >> 8), uint8(bb / n >> 8), 255})
		}
	}
	return dst
}
