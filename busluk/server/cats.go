package main

import (
	"crypto/sha1"
	"encoding/hex"
	"encoding/json"
	"strings"
)

// Справочники отдаются одним сжатым JSON (/v1/meta) с ETag.
// Клиент кэширует его и повторно не скачивает, пока он не изменится.
// Иконки — эмодзи: ноль картинок, ноль трафика.

type Opt struct {
	K string `json:"k"`
	R string `json:"r"`
	T string `json:"t,omitempty"` // пусто = как R
}

type Attr struct {
	K string `json:"k"`
	R string `json:"r"`
	T string `json:"t"`
	Y string `json:"y"`           // n = число, s = выбор
	U string `json:"u,omitempty"` // единица
	O []Opt  `json:"o,omitempty"`
}

type Cat struct {
	I  int      `json:"i"`
	P  int      `json:"p,omitempty"`
	R  string   `json:"r"`
	T  string   `json:"t"`
	E  string   `json:"e,omitempty"`
	A  []string `json:"a,omitempty"`
	kw string
	nx string
}

type City struct {
	I int    `json:"i"`
	G int    `json:"g"` // регион
	R string `json:"r"`
	T string `json:"t"`
}

func opts(s string) []Opt { // "k|Рус|Tkm;k2|..."
	var o []Opt
	for _, p := range strings.Split(s, ";") {
		f := strings.Split(p, "|")
		x := Opt{K: f[0], R: f[1]}
		if len(f) > 2 {
			x.T = f[2]
		}
		o = append(o, x)
	}
	return o
}

func brands(s string) []Opt {
	var o []Opt
	for _, b := range strings.Split(s, ",") {
		o = append(o, Opt{K: strings.ReplaceAll(strings.ToLower(b), " ", "-"), R: b})
	}
	o = append(o, Opt{K: "other", R: "Другая", T: "Başga"})
	return o
}

var attrs = []Attr{
	{K: "brand", R: "Марка", T: "Markasy", Y: "s", O: brands("Toyota,Lexus,Hyundai,Kia,Mercedes-Benz,BMW,Chevrolet,Nissan,Honda,Mitsubishi,Mazda,Ford,Volkswagen,Opel,Audi,Subaru,Land Rover,Lada,GAZ,Daewoo,Haval,Chery,Geely,BYD,Changan,Kamaz,MAN,Howo")},
	{K: "year", R: "Год", T: "Ýyly", Y: "n"},
	{K: "km", R: "Пробег", T: "Geçen ýoly", Y: "n", U: "km"},
	{K: "fuel", R: "Топливо", T: "Ýangyç", Y: "s", O: opts("benzin|Бензин|Benzin;gas|Газ|Gaz;diesel|Дизель|Dizel;hybrid|Гибрид|Gibrid;electro|Электро|Elektrik")},
	{K: "gear", R: "Коробка", T: "Tizlik gutusy", Y: "s", O: opts("auto|Автомат|Awtomat;manual|Механика|Mehanika")},
	{K: "body", R: "Кузов", T: "Kuzow", Y: "s", O: opts("sedan|Седан|Sedan;hatch|Хэтчбек|Hetçbek;wagon|Универсал|Uniwersal;suv|Внедорожник|Ýolsuzlyk;minivan|Минивэн|Miniwen;pickup|Пикап|Pikap;coupe|Купе|Kupe")},
	{K: "rooms", R: "Комнат", T: "Otag sany", Y: "n"},
	{K: "area", R: "Площадь", T: "Meýdany", Y: "n", U: "m²"},
	{K: "floor", R: "Этаж", T: "Gaty", Y: "n"},
	{K: "floors", R: "Этажей в доме", T: "Jaýyň gat sany", Y: "n"},
	{K: "sot", R: "Площадь участка", T: "Ýer meýdany", Y: "n", U: "sot"},
	{K: "repair", R: "Ремонт", T: "Bejergi", Y: "s", O: opts("euro|Евроремонт|Ýewro bejergi;good|Хороший|Gowy;need|Требует ремонта|Bejeriş gerek")},
	{K: "period", R: "Срок аренды", T: "Kärende möhleti", Y: "s", O: opts("month|Помесячно|Aýlyk;day|Посуточно|Gündelik")},
	{K: "cond", R: "Состояние", T: "Ýagdaýy", Y: "s", O: opts("new|Новое|Täze;used|Б/у|Ulanylan")},
	{K: "salary", R: "Зарплата", T: "Aýlyk", Y: "n", U: "TMT"},
	{K: "sched", R: "График", T: "Iş tertibi", Y: "s", O: opts("full|Полный день|Doly gün;part|Неполный день|Doly däl gün;shift|Сменный|Smena;remote|Удалённо|Uzakdan")},
}

func a(s string) []string { return strings.Fields(s) }

var cats = []Cat{
	{I: 1, R: "Транспорт", T: "Ulaglar", E: "🚗", kw: "avto mashina masyn ulag"},
	{I: 101, P: 1, R: "Легковые авто", T: "Ýeňil awtoulaglar", E: "🚙", A: a("brand year km fuel gear body"), kw: "mashina avtomobil masyn sedan car"},
	{I: 102, P: 1, R: "Грузовики", T: "Ýük awtoulaglary", E: "🚚", A: a("brand year km"), kw: "gruzovik kamaz yuk"},
	{I: 103, P: 1, R: "Автобусы и микроавтобусы", T: "Awtobuslar we mikroawtobuslar", E: "🚌", A: a("year km"), kw: "avtobus marshrutka gazel"},
	{I: 104, P: 1, R: "Спецтехника", T: "Ýörite tehnika", E: "🚜", A: a("year"), kw: "ekskavator kran pogruzchik buldozer"},
	{I: 105, P: 1, R: "Сельхозтехника", T: "Oba hojalyk tehnikasy", E: "🚜", A: a("year"), kw: "traktor kombayn"},
	{I: 106, P: 1, R: "Мото и мопеды", T: "Motosikller we mopedler", E: "🏍", A: a("year"), kw: "moto motosikl skuter"},
	{I: 107, P: 1, R: "Запчасти", T: "Ätiýaçlyk şaýlary", E: "⚙️", A: a("cond"), kw: "zapchast detal motor fara bamper"},
	{I: 108, P: 1, R: "Шины и диски", T: "Tekerler we diskler", E: "🛞", A: a("cond"), kw: "shina rezina koleso teker disk"},
	{I: 109, P: 1, R: "Аренда авто", T: "Awtoulag kärende", E: "🔑", kw: "prokat arenda"},
	{I: 110, P: 1, R: "Водный транспорт", T: "Suw ulaglary", E: "🚤", kw: "lodka kater gaýyk"},
	{I: 111, P: 1, R: "Велосипеды", T: "Welosipedler", E: "🚲", A: a("cond"), kw: "velik velosiped"},

	{I: 2, R: "Недвижимость", T: "Gozgalmaýan emläk", E: "🏠", kw: "nedvizhimost jay kvartira"},
	{I: 201, P: 2, R: "Квартиры — продажа", T: "Kwartiralar — satlyk", E: "🏢", A: a("rooms area floor floors repair"), kw: "kvartira jay prodam satlyk elitka"},
	{I: 202, P: 2, R: "Квартиры — аренда", T: "Kwartiralar — kärende", E: "🗝", A: a("rooms area floor period repair"), kw: "kvartira snyat arenda kirey"},
	{I: 203, P: 2, R: "Дома и дачи", T: "Jaýlar we bag jaýlar", E: "🏡", A: a("rooms area sot repair"), kw: "dom hovli jay dacha kottedzh"},
	{I: 204, P: 2, R: "Дома — аренда", T: "Jaý kärende", E: "🏘", A: a("rooms area period"), kw: "dom snyat arenda"},
	{I: 205, P: 2, R: "Участки", T: "Ýer bölekleri", E: "🌳", A: a("sot"), kw: "uchastok zemlya yer"},
	{I: 206, P: 2, R: "Коммерческая недвижимость", T: "Täjirçilik emlägi", E: "🏬", A: a("area period"), kw: "ofis magazin sklad dukan"},
	{I: 207, P: 2, R: "Гаражи", T: "Garažlar", E: "🅿️", kw: "garaj"},
	{I: 208, P: 2, R: "Комнаты", T: "Otaglar", E: "🛏", A: a("area period"), kw: "komnata otag obshezhitie"},

	{I: 3, R: "Услуги мастеров", T: "Ussalaryň hyzmatlary", E: "🛠", kw: "usluga master usta ussa hyzmat"},
	{I: 301, P: 3, R: "Сантехник", T: "Santehnik", E: "🚰", kw: "truba kran unitaz kanalizatsiya"},
	{I: 302, P: 3, R: "Электрик", T: "Elektrik", E: "💡", kw: "provodka rozetka svet tok"},
	{I: 303, P: 3, R: "Ремонт квартир", T: "Kwartira bejergisi", E: "🖌", kw: "remont plitka oboi shtukaturka maler bejergi"},
	{I: 304, P: 3, R: "Строительство", T: "Gurluşyk", E: "🧱", kw: "stroitel kladka beton krysha"},
	{I: 305, P: 3, R: "Мебель на заказ", T: "Sargyt boýunça mebel", E: "🪑", kw: "kuhnya shkaf mebel"},
	{I: 306, P: 3, R: "Ремонт бытовой техники", T: "Öý enjamlaryny bejermek", E: "🧺", kw: "stiralka holodilnik remont"},
	{I: 307, P: 3, R: "Ремонт телефонов и ПК", T: "Telefon we kompýuter bejergisi", E: "📲", kw: "remont telefona noutbuk ekran"},
	{I: 308, P: 3, R: "Кондиционеры", T: "Kondisionerler", E: "❄️", kw: "kondicioner kondisioner montazh zapravka split"},
	{I: 309, P: 3, R: "Автосервис", T: "Awtoserwis", E: "🔧", kw: "sto avtoremont vulkanizatsiya rihtovka"},
	{I: 310, P: 3, R: "Грузоперевозки", T: "Ýük daşamak", E: "📦", kw: "pereezd gruzchik dostavka gazel"},
	{I: 311, P: 3, R: "Такси и трансфер", T: "Taksi we transfer", E: "🚕", kw: "taksi transfer aeroport"},
	{I: 312, P: 3, R: "Уборка", T: "Arassaçylyk", E: "🧹", kw: "uborka klining arassala"},
	{I: 313, P: 3, R: "Красота и здоровье", T: "Gözellik we saglyk", E: "💅", kw: "parikmaher manikyur massazh kosmetolog"},
	{I: 314, P: 3, R: "Репетиторы и курсы", T: "Repetitorlar we kurslar", E: "📚", kw: "repetitor kurs angliyskiy matematika okuw"},
	{I: 315, P: 3, R: "Фото и видео", T: "Surat we wideo", E: "📷", kw: "fotograf videograf syomka"},
	{I: 316, P: 3, R: "Той и праздники", T: "Toý we baýramçylyklar", E: "🎉", kw: "toy svadba tamada muzyka bezeg"},
	{I: 317, P: 3, R: "Швея и ателье", T: "Tikinçi we atelýe", E: "🧵", kw: "shveya poshiv tikinchi"},
	{I: 318, P: 3, R: "Сварка", T: "Kebşirleme", E: "🔥", kw: "svarka svarshik vorota"},
	{I: 319, P: 3, R: "Окна и двери", T: "Penjireler we gapylar", E: "🚪", kw: "okna dveri plastik penjire gapy"},
	{I: 320, P: 3, R: "Мастер на час", T: "Bir sagatlyk ussa", E: "⏱", kw: "master na chas melkiy remont"},
	{I: 321, P: 3, R: "IT и дизайн", T: "IT we dizaýn", E: "💻", kw: "sayt programmist dizayn reklama"},
	{I: 322, P: 3, R: "Юристы и бухгалтеры", T: "Hukukçylar we buhgalterler", E: "⚖️", kw: "yurist buhgalter notarius perevod"},
	{I: 323, P: 3, R: "Прочие услуги", T: "Beýleki hyzmatlar", E: "🧰"},

	{I: 4, R: "Электроника", T: "Elektronika", E: "📱"},
	{I: 401, P: 4, R: "Телефоны", T: "Telefonlar", E: "📱", A: a("cond"), kw: "telefon iphone samsung xiaomi redmi smartfon"},
	{I: 402, P: 4, R: "Компьютеры и ноутбуки", T: "Kompýuterler we noutbuklar", E: "💻", A: a("cond"), kw: "noutbuk kompyuter pk monitor"},
	{I: 403, P: 4, R: "Планшеты", T: "Planşetler", E: "📟", A: a("cond"), kw: "planshet ipad"},
	{I: 404, P: 4, R: "ТВ и видео", T: "Telewizorlar we wideo", E: "📺", A: a("cond"), kw: "televizor tv"},
	{I: 405, P: 4, R: "Аудио", T: "Audio", E: "🎧", A: a("cond"), kw: "naushniki kolonka"},
	{I: 406, P: 4, R: "Фото и камеры", T: "Fotoapparatlar", E: "📸", A: a("cond"), kw: "fotoapparat kamera"},
	{I: 407, P: 4, R: "Игры и приставки", T: "Oýunlar we pristawkalar", E: "🎮", A: a("cond"), kw: "playstation ps5 xbox"},
	{I: 408, P: 4, R: "Аксессуары", T: "Aksessuarlar", E: "🔌", kw: "chehol zaryadka"},
	{I: 409, P: 4, R: "Видеонаблюдение", T: "Wideogözegçilik", E: "📹", kw: "kamera videonablyudenie"},

	{I: 5, R: "Дом и сад", T: "Öý we bag", E: "🛋"},
	{I: 501, P: 5, R: "Мебель", T: "Mebel", E: "🛋", A: a("cond"), kw: "divan krovat stol shkaf"},
	{I: 502, P: 5, R: "Бытовая техника", T: "Öý enjamlary", E: "🧊", A: a("cond"), kw: "holodilnik stiralka pech kondicioner"},
	{I: 503, P: 5, R: "Посуда", T: "Gap-gaç", E: "🍽", kw: "posuda kazan"},
	{I: 504, P: 5, R: "Стройматериалы", T: "Gurluşyk serişdeleri", E: "🪵", kw: "kirpich cement plitka"},
	{I: 505, P: 5, R: "Ковры", T: "Halylar", E: "🧶", kw: "kover haly palas"},
	{I: 506, P: 5, R: "Сад и огород", T: "Bag we bakja", E: "🌱", kw: "sad ogorod rassada"},
	{I: 507, P: 5, R: "Инструменты", T: "Gurallar", E: "🔨", kw: "instrument drel bolgarka"},
	{I: 508, P: 5, R: "Текстиль", T: "Dokma önümleri", E: "🧣", kw: "shtory postel"},

	{I: 6, R: "Одежда и обувь", T: "Egin-eşik we aýakgap", E: "👗"},
	{I: 601, P: 6, R: "Женская одежда", T: "Aýal egin-eşikleri", E: "👗", A: a("cond"), kw: "platye koynek"},
	{I: 602, P: 6, R: "Мужская одежда", T: "Erkek egin-eşikleri", E: "👔", A: a("cond"), kw: "kostyum kurtka"},
	{I: 603, P: 6, R: "Обувь", T: "Aýakgaplar", E: "👟", A: a("cond"), kw: "krossovki tufli"},
	{I: 604, P: 6, R: "Национальная одежда", T: "Milli egin-eşikler", E: "🪡", kw: "kurte don telpek"},
	{I: 605, P: 6, R: "Украшения и часы", T: "Şaý-sepler we sagatlar", E: "💍", kw: "zoloto kolco chasy"},
	{I: 606, P: 6, R: "Сумки", T: "Sumkalar", E: "👜"},

	{I: 7, R: "Детский мир", T: "Çagalar dünýäsi", E: "🧸"},
	{I: 701, P: 7, R: "Детская одежда", T: "Çaga egin-eşikleri", E: "👕", A: a("cond")},
	{I: 702, P: 7, R: "Игрушки", T: "Oýunjaklar", E: "🧸"},
	{I: 703, P: 7, R: "Коляски и автокресла", T: "Çaga arabalary we oturgyçlary", E: "👶", A: a("cond"), kw: "kolyaska"},
	{I: 704, P: 7, R: "Детская мебель", T: "Çaga mebeli", E: "🛏"},

	{I: 8, R: "Работа", T: "Iş", E: "💼"},
	{I: 801, P: 8, R: "Вакансии", T: "Boş iş orunlary", E: "📋", A: a("salary sched"), kw: "rabota vakansiya ish"},
	{I: 802, P: 8, R: "Резюме", T: "Rezýumeler", E: "🙋", A: a("sched"), kw: "ishu rabotu rezyume"},

	{I: 9, R: "Животные", T: "Haýwanlar", E: "🐑"},
	{I: 901, P: 9, R: "Скот", T: "Mal", E: "🐄", kw: "korova baran koyun dowar sygyr"},
	{I: 902, P: 9, R: "Лошади", T: "Atlar", E: "🐎", kw: "loshad ahalteke at"},
	{I: 903, P: 9, R: "Собаки", T: "Itler", E: "🐕", kw: "alabay sobaka it"},
	{I: 904, P: 9, R: "Кошки", T: "Pişikler", E: "🐈"},
	{I: 905, P: 9, R: "Птицы", T: "Guşlar", E: "🐓", kw: "kury tovuk golub"},
	{I: 906, P: 9, R: "Корма и товары", T: "Iýmler we harytlar", E: "🦴"},

	{I: 10, R: "Сельское хозяйство", T: "Oba hojalygy", E: "🌾"},
	{I: 1001, P: 10, R: "Семена и саженцы", T: "Tohumlar we nahallar", E: "🌱"},
	{I: 1002, P: 10, R: "Урожай и продукты", T: "Hasyl we azyk", E: "🍅", kw: "ovoshi frukty bal"},
	{I: 1003, P: 10, R: "Удобрения", T: "Dökünler", E: "🧪"},
	{I: 1004, P: 10, R: "Оборудование и теплицы", T: "Enjamlar we teplisalar", E: "🏗", kw: "teplica kapelnyy poliv"},

	{I: 11, R: "Бизнес и оборудование", T: "Biznes we enjamlar", E: "🏭"},
	{I: 1101, P: 11, R: "Готовый бизнес", T: "Taýýar biznes", E: "🏪"},
	{I: 1102, P: 11, R: "Оборудование для бизнеса", T: "Biznes üçin enjamlar", E: "⚙️", A: a("cond"), kw: "stanok oborudovanie"},
	{I: 1103, P: 11, R: "Торговое оборудование", T: "Söwda enjamlary", E: "🛒", A: a("cond"), kw: "vitrina kassa"},

	{I: 12, R: "Хобби и отдых", T: "Hobbi we dynç alyş", E: "🎸"},
	{I: 1201, P: 12, R: "Спорт", T: "Sport", E: "⚽", kw: "trenazher velotrenazher"},
	{I: 1202, P: 12, R: "Музыкальные инструменты", T: "Saz gurallary", E: "🎻", kw: "dutar gitara pianino"},
	{I: 1203, P: 12, R: "Книги", T: "Kitaplar", E: "📖"},
	{I: 1204, P: 12, R: "Коллекционирование", T: "Kolleksiýa", E: "🪙", kw: "monety marki"},
	{I: 1205, P: 12, R: "Туризм и рыбалка", T: "Syýahat we balyk tutmak", E: "🎣", kw: "palatka udochka"},
	{I: 1206, P: 12, R: "Билеты и путёвки", T: "Biletler we ýollamalar", E: "🎫"},

	{I: 13, R: "Отдам даром", T: "Mugt berýärin", E: "🎁", kw: "besplatno mugt darom"},
}

var cities = []City{
	{1, 1, "Ашхабад", "Aşgabat"}, {2, 7, "Аркадаг", "Arkadag"},
	{10, 2, "Анев", "Änew"}, {11, 2, "Гёкдепе", "Gökdepe"}, {12, 2, "Теджен", "Tejen"}, {13, 2, "Бахарлы", "Baharly"},
	{14, 2, "Каахка", "Kaka"}, {15, 2, "Серахс", "Sarahs"}, {16, 2, "Бабадайхан", "Babadaýhan"}, {17, 2, "Ак бугдай", "Ak bugdaý"},
	{20, 3, "Балканабат", "Balkanabat"}, {21, 3, "Туркменбаши", "Türkmenbaşy"}, {22, 3, "Сердар", "Serdar"},
	{23, 3, "Берекет", "Bereket"}, {24, 3, "Гумдаг", "Gumdag"}, {25, 3, "Хазар", "Hazar"}, {26, 3, "Махтумкули", "Magtymguly"},
	{27, 3, "Эсенгулы", "Esenguly"}, {28, 3, "Этрек", "Etrek"}, {29, 3, "Аваза", "Awaza"},
	{30, 4, "Дашогуз", "Daşoguz"}, {31, 4, "Кёнеургенч", "Köneürgenç"}, {32, 4, "Гёроглы", "Görogly"},
	{33, 4, "Губадаг", "Gubadag"}, {34, 4, "Болдумсаз", "Boldumsaz"}, {35, 4, "Акдепе", "Akdepe"}, {36, 4, "Рухубелент", "Ruhubelent"},
	{40, 5, "Туркменабат", "Türkmenabat"}, {41, 5, "Сейди", "Seýdi"}, {42, 5, "Керки", "Kerki"}, {43, 5, "Фарап", "Farap"},
	{44, 5, "Дарганата", "Darganata"}, {45, 5, "Халач", "Halaç"}, {46, 5, "Кёйтендаг", "Köýtendag"}, {47, 5, "Гарабекевюл", "Garabekewül"}, {48, 5, "Саят", "Saýat"},
	{50, 6, "Мары", "Mary"}, {51, 6, "Байрамали", "Baýramaly"}, {52, 6, "Ёлётен", "Ýolöten"}, {53, 6, "Мургап", "Murgap"},
	{54, 6, "Сакарчаге", "Sakarçäge"}, {55, 6, "Тагтабазар", "Tagtabazar"}, {56, 6, "Серхетабат", "Serhetabat"},
	{57, 6, "Векильбазар", "Wekilbazar"}, {58, 6, "Туркменгала", "Türkmengala"}, {59, 6, "Огузхан", "Oguzhan"},
}

var regions = []City{
	{1, 0, "Ашхабад", "Aşgabat"}, {7, 0, "Аркадаг", "Arkadag"}, {2, 0, "Ахалский велаят", "Ahal welaýaty"},
	{3, 0, "Балканский велаят", "Balkan welaýaty"}, {4, 0, "Дашогузский велаят", "Daşoguz welaýaty"},
	{5, 0, "Лебапский велаят", "Lebap welaýaty"}, {6, 0, "Марыйский велаят", "Mary welaýaty"},
}

var (
	catByID  = map[int]*Cat{}
	cityByID = map[int]*City{}
	attrByK  = map[string]*Attr{}
	metaJSON []byte
	metaTag  string
)

type Prices struct {
	Bump  int64 `json:"bump"`
	Vip7  int64 `json:"vip7"`
	Vip30 int64 `json:"vip30"`
}

func initMeta(p Prices) {
	for i := range cats {
		c := &cats[i]
		catByID[c.I] = c
		c.nx = norm(c.R + " " + c.T + " " + c.kw)
	}
	for i := range cities {
		cityByID[cities[i].I] = &cities[i]
	}
	for i := range attrs {
		attrByK[attrs[i].K] = &attrs[i]
	}
	metaJSON, _ = json.Marshal(map[string]any{"v": 1, "cats": cats, "attrs": attrs, "cities": cities, "regions": regions, "prices": p})
	h := sha1.Sum(metaJSON)
	metaTag = `"` + hex.EncodeToString(h[:8]) + `"`
}

// isLeaf: объявление можно разместить только в конечной категории.
func isLeaf(id int) bool {
	if catByID[id] == nil {
		return false
	}
	for _, c := range cats {
		if c.P == id {
			return false
		}
	}
	return true
}

// catTree: сама категория и все её дочерние (для фильтра по родителю).
func catTree(id int) []int {
	out := []int{id}
	for _, c := range cats {
		if c.P == id {
			out = append(out, c.I)
		}
	}
	return out
}

// catAttrs: атрибуты категории с учётом родителя.
func catAttrs(id int) []string {
	c := catByID[id]
	if c == nil {
		return nil
	}
	if len(c.A) == 0 && c.P != 0 {
		return catAttrs(c.P)
	}
	return c.A
}

// suggestCats: подсказка категорий по запросу («кварт» -> Квартиры — продажа/аренда).
func suggestCats(q string) []int {
	toks := strings.Fields(norm(q))
	if len(toks) == 0 {
		return nil
	}
	var out []int
	for _, c := range cats {
		if c.P == 0 && len(catTree(c.I)) > 1 {
			continue
		}
		ok := true
		for _, t := range toks {
			if len([]rune(t)) < 3 || !strings.Contains(c.nx, t) {
				ok = false
				break
			}
		}
		if ok {
			out = append(out, c.I)
			if len(out) == 4 {
				break
			}
		}
	}
	return out
}
