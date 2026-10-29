"""Year plan grades 1–12, built on international general-education standards
(UNESCO/IB/Cambridge-style progression), not tied to any ministry programme.
Each topic is "tk|ru". Run: python3 plan.py → plan.json"""
import json

P = {}
P[1] = {
 "turkmen": ["Sesler we harplar|Звуки и буквы", "Çekimli sesler|Гласные звуки", "Çekimsiz sesler|Согласные звуки", "Bogun|Слог", "Söz|Слово", "Sözlem|Предложение"],
 "reading": ["Elipbiý bilen tanyşlyk|Знакомство с алфавитом", "Bogunlap okamak|Чтение по слогам", "Gysga sözler|Короткие слова", "Kiçi hekaýalar|Маленькие рассказы", "Haýwanlar hakynda ertekiler|Сказки о животных", "Tapmaçalar|Загадки"],
 "math": ["1-den 10-a çenli sanlar|Числа от 1 до 10", "Köp, az, deň|Больше, меньше, равно", "10-a çenli goşmak|Сложение до 10", "10-a çenli aýyrmak|Вычитание до 10", "Geometrik şekiller|Геометрические фигуры", "20-ä çenli sanlar|Числа до 20"],
 "world": ["Men we maşgalam|Я и моя семья", "Mekdep|Школа", "Ýylyň pasyllary|Времена года", "Öý haýwanlary|Домашние животные", "Ösümlikler|Растения", "Saglyk we arassaçylyk|Здоровье и гигиена"],
 "russian": ["Tanyşlyk: Здравствуй!|Знакомство: Здравствуй!", "Reňkler|Цвета", "Sanlar 1–10|Числа 1–10", "Maşgala|Семья", "Haýwanlar|Животные", "Mekdep goşlary|Школьные принадлежности"],
 "english": ["Hello! Salamlaşmak|Hello! Приветствие", "Colours — reňkler|Colours — цвета", "Numbers 1–10|Numbers 1–10", "Family — maşgala|Family — семья", "Animals — haýwanlar|Animals — животные", "Toys — oýnawaçlar|Toys — игрушки"],
}
P[2] = {
 "turkmen": ["Ýogyn we inçe çekimliler|Твёрдые и мягкие гласные", "Sözüň manysy|Значение слова", "At|Имя существительное", "Sypat|Имя прилагательное", "Işlik|Глагол", "Sözlemiň görnüşleri|Виды предложений"],
 "reading": ["Goşgy we ritm|Стихи и ритм", "Halk ertekileri|Народные сказки", "Tebigat hakynda hekaýalar|Рассказы о природе", "Dostluk hakynda|О дружбе", "Nakyllar|Пословицы", "Tekstiň esasy pikiri|Главная мысль текста"],
 "math": ["100-e çenli sanlar|Числа до 100", "Onluklar we birlikler|Десятки и единицы", "100-e çenli goşmak we aýyrmak|Сложение и вычитание до 100", "Köpeltmek näme?|Что такое умножение", "Wagt we sagat|Время и часы", "Uzynlyk ölçegleri|Меры длины"],
 "world": ["Adamyň bedeni|Тело человека", "Howa we pasyllar|Погода и сезоны", "Suw we onuň ýagdaýlary|Вода и её состояния", "Ýabany haýwanlar|Дикие животные", "Ýol hereketiniň düzgünleri|Правила дорожного движения", "Biziň planetamyz Ýer|Наша планета Земля"],
 "russian": ["Rus elipbiýi|Русский алфавит", "Öýüm|Мой дом", "Iýmit|Еда", "Egin-eşik|Одежда", "Hepdäniň günleri|Дни недели", "Hereket işlikleri|Глаголы движения"],
 "english": ["The alphabet — elipbiý|The alphabet — алфавит", "My body — bedenim|My body — тело", "Food — iýmit|Food — еда", "Clothes — eşikler|Clothes — одежда", "Days of the week|Days of the week — дни недели", "I can… — men başarýaryn|I can… — я умею"],
}
P[3] = {
 "turkmen": ["Sözüň düzümi: kök we goşulma|Состав слова: корень и аффикс", "Köplük san|Множественное число", "Düşümler bilen tanyşlyk|Знакомство с падежами", "Işligiň zamanlary|Времена глагола", "Çalyşmalar|Местоимения", "Hat ýazmak|Пишем письмо"],
 "reading": ["Erteki we hekaýa|Сказка и рассказ", "Gahrymanlar we häsiýetler|Герои и их характеры", "Dünýä halklarynyň ertekileri|Сказки народов мира", "Basnýa|Басня", "Goşgy we kapiýa|Стих и рифма", "Okalany gürrüň bermek|Пересказ прочитанного"],
 "math": ["Köpeltmek tablisasy|Таблица умножения", "Bölmek|Деление", "Galyndyly bölmek|Деление с остатком", "1000-e çenli sanlar|Числа до 1000", "Perimetr|Периметр", "Meseleler çözmek|Решение задач"],
 "world": ["Gün ulgamy|Солнечная система", "Howa we atmosfera|Воздух и атмосфера", "Toprak|Почва", "Iýmit zynjyry|Пищевая цепь", "Materikler we ummanlar|Материки и океаны", "Tebigaty goramak|Охрана природы"],
 "russian": ["At (существительное)|Существительное", "Atlaryň jynsy|Род существительных", "Sypat (прилагательное)|Прилагательное", "Işlik (глагол)|Глагол", "Meniň günüm|Мой день", "Howa|Погода"],
 "english": ["There is / there are|There is / there are", "My house — öýüm|My house — мой дом", "Present Continuous|Present Continuous", "Have got|Have got", "Can / can't|Can / can't", "Seasons and weather|Seasons and weather — погода"],
}
P[4] = {
 "turkmen": ["Sözlem agzalary|Члены предложения", "Eýe we habar|Подлежащее и сказуемое", "San (söz topary)|Числительное", "Hal|Наречие", "Baglaýjylar|Союзы", "Düzme ýazmak|Сочинение"],
 "reading": ["Mif we rowaýat|Миф и легенда", "Dessan bilen tanyşlyk|Знакомство с дастаном", "Fantastika|Фантастика", "Terjimehal|Биография", "Pýesa|Пьеса", "Kitap saýlamak|Как выбрать книгу"],
 "math": ["Köp belgili sanlar|Многозначные числа", "Sütün bilen köpeltmek|Умножение столбиком", "Burç bilen bölmek|Деление уголком", "Ülüşler we droblar|Доли и дроби", "Meýdan|Площадь", "Tizlik, wagt, aralyk|Скорость, время, расстояние"],
 "world": ["Tebigy zolaklar|Природные зоны", "Peýdaly gazylyp alynýan baýlyklar|Полезные ископаемые", "Energiýa çeşmeleri|Источники энергии", "Adamyň iç organlary|Внутренние органы человека", "Gadymy siwilizasiýalar|Древние цивилизации", "Karta we kompas|Карта и компас"],
 "russian": ["Predloglar|Предлоги", "Köplük san|Множественное число", "Öten zaman|Прошедшее время", "Geljek zaman|Будущее время", "Meniň şäherim|Мой город", "Dükanda|В магазине"],
 "english": ["Past Simple: was / were|Past Simple: was / were", "Past Simple: regular verbs|Past Simple: правильные глаголы", "Comparatives|Сравнительная степень", "My town — şäherim|My town — мой город", "Shopping — söwda|Shopping — покупки", "Jobs — hünärler|Jobs — профессии"],
}
P[5] = {
 "turkmen": ["Fonetika|Фонетика", "Sinonim we antonim|Синонимы и антонимы", "Söz ýasalyşy|Словообразование", "Atyň düşümleri|Падежи существительного", "Işligiň şekilleri|Формы глагола", "Dilden we ýazuwdan gürrüň|Устная и письменная речь"],
 "literature": ["Edebiýat näme?|Что такое литература", "Halk döredijiligi|Фольклор", "«Görogly» eposy|Эпос «Гёроглы»", "Dünýä ertekileri|Сказки мира", "Hekaýanyň gurluşy|Строение рассказа", "Şygryň esaslary|Основы стихосложения"],
 "math": ["Natural sanlar|Натуральные числа", "Bölünijilik alamatlary|Признаки делимости", "Adaty droblar|Обыкновенные дроби", "Onluk droblar|Десятичные дроби", "Göterimler|Проценты", "Burçlar we olary ölçemek|Углы и их измерение"],
 "russian": ["Fonetika|Фонетика", "Sözüň düzümi|Состав слова", "Urgusyz çekimliler|Безударные гласные", "Işligiň üýtgeýşi|Спряжение глагола", "Söz düzümi|Словосочетание", "Tekst we onuň temasy|Текст и его тема"],
 "english": ["Present Simple vs Continuous|Present Simple и Continuous", "Past Simple: irregular verbs|Past Simple: неправильные глаголы", "Countable / uncountable|Исчисляемые и неисчисляемые", "Going to|Going to", "Hobbies — gyzyklanmalar|Hobbies — увлечения", "Writing an email|Пишем email"],
 "history": ["Taryh we taryhy çeşmeler|История и исторические источники", "Daş asyry|Каменный век", "Gadymy Müsür|Древний Египет", "Mesopotamiýa|Месопотамия", "Gadymy Gresiýa|Древняя Греция", "Gadymy Rim|Древний Рим"],
 "informatics": ["Kompýuteriň bölekleri|Устройство компьютера", "Faýllar we bukjalar|Файлы и папки", "Klawiatura bilen işlemek|Работа с клавиатурой", "Algoritm näme?|Что такое алгоритм", "Internetde howpsuzlyk|Безопасность в интернете", "Tekst redaktory|Текстовый редактор"],
}
P[6] = {
 "turkmen": ["Sypatlaryň derejeleri|Степени прилагательных", "Sanlaryň görnüşleri|Разряды числительных", "Çalyşmalaryň görnüşleri|Разряды местоимений", "Buýruk we şert formalary|Повелительная и условная формы", "Durnukly söz düzümleri|Фразеологизмы", "Arza ýazmak|Пишем заявление"],
 "literature": ["Dessanlar|Дастаны", "Nusgawy türkmen şahyrlary|Классические туркменские поэты", "Ezop we Krylow|Эзоп и Крылов", "Sýužet we kompozisiýa|Сюжет и композиция", "Dünýä çagalar edebiýaty|Мировая детская литература", "Gahrymanyň obrazy|Образ героя"],
 "math": ["Bitin sanlar|Целые числа", "Otrisatel sanlar bilen amallar|Действия с отрицательными числами", "Gatnaşyk we proporsiýa|Отношения и пропорции", "Koordinata tekizligi|Координатная плоскость", "Aňlatmalary ýönekeýleşdirmek|Упрощение выражений", "Töwerek we tegelek|Окружность и круг"],
 "russian": ["Sinonimler we antonimler|Синонимы и антонимы", "Frazeologizmler|Фразеологизмы", "Sypatyň deňeşdirme derejeleri|Степени сравнения прилагательных", "San (числительное)|Имя числительное", "Çalyşma (местоимение)|Местоимение", "Iş haty|Деловое письмо"],
 "english": ["Present Perfect|Present Perfect", "Past Continuous|Past Continuous", "Will vs going to|Will и going to", "Must / should|Must / should", "Travel — syýahat|Travel — путешествия", "Describing people|Описание внешности"],
 "history": ["Gadymy Hindistan|Древняя Индия", "Gadymy Hytaý|Древний Китай", "Parfiýa we Nusaý|Парфия и Ниса", "Beýik Ýüpek ýoly|Великий Шёлковый путь", "Rim imperiýasynyň dargamagy|Падение Римской империи", "Orta asyrlaryň başlangyjy|Начало Средневековья"],
 "informatics": ["Maglumat we onuň görnüşleri|Информация и её виды", "Prezentasiýa döretmek|Создание презентации", "Elektron tablisalar|Электронные таблицы", "Algoritmiň görnüşleri|Виды алгоритмов", "Blok-shemalar|Блок-схемы", "Scratch-da programmirleme|Программирование в Scratch"],
 "biology": ["Janlylaryň häsiýetleri|Свойства живого", "Mikroskop|Микроскоп", "Bakteriýalar we kömelekler|Бактерии и грибы", "Ösümligiň gurluşy|Строение растения", "Fotosintez|Фотосинтез", "Ösümlikleriň köpelişi|Размножение растений"],
 "geography": ["Ýeriň şekili we hereketi|Форма и движение Земли", "Karta we masştab|Карта и масштаб", "Giňlik we uzaklyk|Широта и долгота", "Litosfera|Литосфера", "Gidrosfera|Гидросфера", "Atmosfera we howa|Атмосфера и погода"],
}
P[7] = {
 "turkmen": ["Aýyklaýjy, doldurgyç, hal|Определение, дополнение, обстоятельство", "Goşma sözlemler|Сложные предложения", "Göni we gytaklaýyn gürrüň|Прямая и косвенная речь", "Dyngy belgileri|Знаки препинания", "Publisistik stil|Публицистический стиль", "Beýan ýazmak|Изложение"],
 "literature": ["«Gorkut ata» kitaby|«Книга Деде Коркута»", "Firdöwsi we «Şanama»|Фирдоуси и «Шахнаме»", "Nowella|Новелла", "Ballada|Баллада", "Satira we ýumor|Сатира и юмор", "Lirika|Лирика"],
 "math": ["Aňlatmalar we toždestwolar|Выражения и тождества", "Derejeler|Степени", "Birağzalar we köpağzalar|Одночлены и многочлены", "Gysga köpeltmek formulalary|Формулы сокращённого умножения", "Funksiýa we grafik|Функция и график", "Deňlemeler ulgamy|Системы уравнений"],
 "geometry": ["Nokat, göni çyzyk, burç|Точка, прямая, угол", "Üçburçluklar|Треугольники", "Üçburçluklaryň deňlik nyşanlary|Признаки равенства треугольников", "Parallel göni çyzyklar|Параллельные прямые", "Üçburçlugyň burçlarynyň jemi|Сумма углов треугольника", "Gurmaga degişli meseleler|Задачи на построение"],
 "physics": ["Fizika näme öwrenýär|Что изучает физика", "Maddanyň gurluşy|Строение вещества", "Massa we dykyzlyk|Масса и плотность", "Güýç we agyrlyk güýji|Сила и сила тяжести", "Basyş|Давление", "Arhimed güýji|Сила Архимеда"],
 "biology": ["Haýwanlaryň klassifikasiýasy|Классификация животных", "Oňurgasyzlar|Беспозвоночные", "Mör-möjekler|Насекомые", "Balyklar|Рыбы", "Guşlar|Птицы", "Süýdemdirijiler|Млекопитающие"],
 "geography": ["Materikler|Материки", "Afrika|Африка", "Ýewraziýa|Евразия", "Amerika materikleri|Америка", "Awstraliýa we Antarktida|Австралия и Антарктида", "Dünýä ummany|Мировой океан"],
 "history": ["Arap halyfaty we ylym|Арабский халифат и наука", "Orta asyr Ýewropasy|Средневековая Европа", "Mongol imperiýasy|Монгольская империя", "Timur we Timurylar|Тимур и Тимуриды", "Biruni we Ibn Sina|Бируни и Ибн Сина", "Beýik geografik açyşlar|Великие географические открытия"],
 "russian": ["Işlik ortak (причастие)|Причастие", "Hal işlik (деепричастие)|Деепричастие", "Hal (наречие)|Наречие", "Predloglar we baglaýjylar|Предлоги и союзы", "Bölejikler|Частицы", "Düzme-beýan|Сочинение-описание"],
 "english": ["Present Perfect vs Past Simple|Present Perfect и Past Simple", "First conditional|Первый тип условных", "Passive voice: present|Пассивный залог: настоящее", "Relative clauses|Относительные придаточные", "Phrasal verbs|Фразовые глаголы", "Writing a story|Пишем рассказ"],
 "informatics": ["Kompýuter arhitekturasy|Архитектура компьютера", "Operasion ulgamlar|Операционные системы", "Tablisalarda formulalar|Формулы в таблицах", "Kompýuter torlary|Компьютерные сети", "Python bilen tanyşlyk|Знакомство с Python", "Şertli operatorlar|Условные операторы"],
}
P[8] = {
 "turkmen": ["Ýönekeý sözlemiň sintaksisi|Синтаксис простого предложения", "Bir düzümli sözlemler|Односоставные предложения", "Birjynsly agzalar|Однородные члены", "Ýüzlenme we giriş sözler|Обращение и вводные слова", "Ylmy stil|Научный стиль", "Esse ýazmak|Пишем эссе"],
 "literature": ["Nyzamy we «Hamsa»|Низами и «Хамсе»", "Şekspir|Шекспир", "Mollanepes|Моллапепес", "Andalyp we Seýdi|Андалиб и Сейди", "Romantizm|Романтизм", "Drama žanry|Жанр драмы"],
 "math": ["Kwadrat kökler|Квадратные корни", "Kwadrat deňlemeler|Квадратные уравнения", "Wiýetiň teoremasy|Теорема Виета", "Rasional droblar|Рациональные дроби", "Deňsizlikler|Неравенства", "Statistikanyň esaslary|Основы статистики"],
 "geometry": ["Dörtburçluklar|Четырёхугольники", "Parallelogram we trapesiýa|Параллелограмм и трапеция", "Şekilleriň meýdanlary|Площади фигур", "Pifagoryň teoremasy|Теорема Пифагора", "Meňzeş üçburçluklar|Подобные треугольники", "Töwerek|Окружность"],
 "physics": ["Ýylylyk hadysalary|Тепловые явления", "Ýylylyk mukdary|Количество теплоты", "Maddanyň agregat ýagdaýlary|Агрегатные состояния", "Elektrik zarýady|Электрический заряд", "Tok güýji we naprýaženiýe|Сила тока и напряжение", "Omuň kanuny|Закон Ома"],
 "chemistry": ["Himiýa näme öwrenýär|Что изучает химия", "Arassa maddalar we garyndylar|Чистые вещества и смеси", "Himiki elementler we formulalar|Химические элементы и формулы", "Walentlik|Валентность", "Himiki reaksiýalar|Химические реакции", "Kislorod we suw|Кислород и вода"],
 "biology": ["Adamyň bedeniniň gurluşy|Строение тела человека", "Süňk-myşsa ulgamy|Опорно-двигательная система", "Gan we gan aýlanyş|Кровь и кровообращение", "Dem alyş|Дыхание", "Iýmit siňdiriş|Пищеварение", "Nerw ulgamy|Нервная система"],
 "geography": ["Merkezi Aziýanyň tebigaty|Природа Центральной Азии", "Hazar deňzi|Каспийское море", "Howa guşaklyklary|Климатические пояса", "Dünýäniň ilaty|Население мира", "Tebigy baýlyklar|Природные ресурсы", "Ekologiki meseleler|Экологические проблемы"],
 "history": ["Galkynyş döwri|Эпоха Возрождения", "Ylmy rewolýusiýa|Научная революция", "Senagat öwrülişigi|Промышленная революция", "ABŞ-nyň garaşsyzlygy|Независимость США", "Fransuz rewolýusiýasy|Французская революция", "XIX asyrda ylym we tehnika|Наука и техника XIX века"],
 "russian": ["Baş agzalar|Главные члены предложения", "Ikinji derejeli agzalar|Второстепенные члены", "Bir düzümli sözlemler|Односоставные предложения", "Birjynsly agzalar|Однородные члены", "Aýratynlaşdyrma|Обособленные члены", "Gürleýiş stilleri|Стили речи"],
 "english": ["Present Perfect Continuous|Present Perfect Continuous", "Second conditional|Второй тип условных", "Passive voice: past|Пассивный залог: прошедшее", "Reported speech|Косвенная речь", "Gerund and infinitive|Герундий и инфинитив", "Opinion essay|Эссе-мнение"],
 "informatics": ["Sikller|Циклы", "Sanawlar|Списки", "Funksiýalar|Функции", "Maglumat bazalary|Базы данных", "HTML: web-sahypa|HTML: веб-страница", "Kiberhowpsuzlyk|Кибербезопасность"],
}
P[9] = {
 "turkmen": ["Goşma sözlemiň görnüşleri|Виды сложных предложений", "Eýerjeňli goşma sözlem|Сложноподчинённое предложение", "Deňeçer goşma sözlem|Сложносочинённое предложение", "Baglaýjysyz goşma sözlem|Бессоюзное предложение", "Stilistika|Стилистика", "Çykyş etmek sungaty|Ораторское искусство"],
 "literature": ["XX asyr türkmen prozasy|Туркменская проза XX века", "Berdi Kerbabaýew|Берды Кербабаев", "Puşkin|Пушкин", "Realizm|Реализм", "Dünýä romanynyň ussatlary|Мастера мирового романа", "Edebi tankyt|Литературная критика"],
 "math": ["Kwadrat funksiýa|Квадратичная функция", "Deňsizlikler ulgamy|Системы неравенств", "Arifmetiki progressiýa|Арифметическая прогрессия", "Geometrik progressiýa|Геометрическая прогрессия", "Ähtimallyk|Вероятность", "Kombinatorika|Комбинаторика"],
 "geometry": ["Wektorlar|Векторы", "Koordinatalar usuly|Метод координат", "Sinus, kosinus, tangens|Синус, косинус, тангенс", "Sinuslar we kosinuslar teoremasy|Теоремы синусов и косинусов", "Dogry köpburçluklar|Правильные многоугольники", "Töweregiň uzynlygy we tegelegiň meýdany|Длина окружности и площадь круга"],
 "physics": ["Mehaniki hereket|Механическое движение", "Nýutonyň kanunlary|Законы Ньютона", "Impuls|Импульс", "Iş we energiýa|Работа и энергия", "Yrgyldylar we tolkunlar|Колебания и волны", "Ses|Звук"],
 "chemistry": ["Oksidler|Оксиды", "Kislotalar|Кислоты", "Esaslar|Основания", "Duzlar|Соли", "Döwürleýin kanun|Периодический закон", "Himiki baglanyşyk|Химическая связь"],
 "biology": ["Genetikanyň esaslary|Основы генетики", "Mendeliň kanunlary|Законы Менделя", "DNK we gen|ДНК и ген", "Ewolýusiýa|Эволюция", "Ekoulgamlar|Экосистемы", "Biosfera|Биосфера"],
 "geography": ["Dünýäniň syýasy kartasy|Политическая карта мира", "Dünýä hojalygy|Мировое хозяйство", "Energetika|Энергетика", "Ulag|Транспорт", "Oba hojalygy|Сельское хозяйство", "Globalizasiýa|Глобализация"],
 "history": ["Birinji jahan urşy|Первая мировая война", "Iki urşuň arasynda dünýä|Мир между войнами", "Ikinji jahan urşy|Вторая мировая война", "BMG-niň döredilmegi|Создание ООН", "Kosmos asyry|Космическая эра", "Sanly rewolýusiýa|Цифровая революция"],
 "russian": ["Sylanyşykly goşma sözlem|Сложносочинённое предложение", "Eýerjeňli goşma sözlem|Сложноподчинённое предложение", "Baglaýjysyz goşma sözlem|Бессоюзное сложное предложение", "Göni we gytaklaýyn gürrüň|Прямая и косвенная речь", "Sitata getirmek|Цитирование", "Düzme-pikirlenme|Сочинение-рассуждение"],
 "english": ["Third conditional|Третий тип условных", "Modals of deduction|Модальные глаголы предположения", "Passive: all tenses|Пассив: все времена", "Linking words|Слова-связки", "Collocations|Коллокации", "Formal letter|Официальное письмо"],
 "informatics": ["Algoritmiň çylşyrymlylygy|Сложность алгоритмов", "Gözleg we tertiplemek|Поиск и сортировка", "Obýekte gönükdirilen programmirleme|Объектно-ориентированное программирование", "CSS bilen dizaýn|Дизайн с CSS", "Maglumatlary wizualizasiýa|Визуализация данных", "Emeli aň bilen tanyşlyk|Введение в искусственный интеллект"],
}
P[10] = {
 "turkmen": ["Dil we jemgyýet|Язык и общество", "Türki diller maşgalasy|Тюркская языковая семья", "Edebi dil we şiweler|Литературный язык и диалекты", "Sözlükler|Словари", "Orfografiýa kadalary|Орфографические нормы", "Işewür hat alyşmak|Деловая переписка"],
 "literature": ["Gomer|Гомер", "Dante|Данте", "Servantes|Сервантес", "Gýote|Гёте", "Tolstoý|Толстой", "Dostoýewskiý|Достоевский"],
 "math": ["Trigonometrik funksiýalar|Тригонометрические функции", "Trigonometrik deňlemeler|Тригонометрические уравнения", "Derejeli funksiýa|Степенная функция", "Görkezijili funksiýa|Показательная функция", "Logarifmler|Логарифмы", "Logarifmik deňlemeler|Логарифмические уравнения"],
 "geometry": ["Stereometriýanyň aksiomalary|Аксиомы стереометрии", "Giňişlikde parallellik|Параллельность в пространстве", "Giňişlikde perpendikulýarlyk|Перпендикулярность в пространстве", "Köpgranlyklar|Многогранники", "Prizma|Призма", "Piramida|Пирамида"],
 "physics": ["Kinematika|Кинематика", "Töwerek boýunça hereket|Движение по окружности", "Bütindünýä dartyşma kanuny|Закон всемирного тяготения", "Molekulýar-kinetik nazaryýet|Молекулярно-кинетическая теория", "Gaz kanunlary|Газовые законы", "Termodinamika|Термодинамика"],
 "chemistry": ["Organiki himiýa|Органическая химия", "Alkanlar|Алканы", "Alkenler we alkinler|Алкены и алкины", "Arenler|Арены", "Spirtler|Спирты", "Nebit we tebigy gaz|Нефть и природный газ"],
 "biology": ["Öýjügiň himiki düzümi|Химический состав клетки", "Beloklar|Белки", "Fermentler|Ферменты", "Mitoz we meýoz|Митоз и мейоз", "Metabolizm|Метаболизм", "Wiruslar|Вирусы"],
 "geography": ["Ýewropa|Европа", "Aziýa|Азия", "Afrikanyň ýurtlary|Страны Африки", "Amerikanyň ýurtlary|Страны Америки", "Okeaniýa|Океания", "Global meseleler|Глобальные проблемы"],
 "history": ["Siwilizasiýa düşünjesi|Понятие цивилизации", "Dünýä dinleriniň taryhy|История мировых религий", "Imperiýalar döwri|Эпоха империй", "Kolonializm|Колониализм", "Demokratiýanyň ösüşi|Развитие демократии", "Ylmyň taryhy|История науки"],
 "russian": ["Leksika we frazeologiýa|Лексика и фразеология", "Morfemika|Морфемика", "Garaşsyz söz toparlary|Самостоятельные части речи", "Kömekçi söz toparlary|Служебные части речи", "Н и НН|Н и НН", "Gürleýiş medeniýeti|Культура речи"],
 "english": ["Mixed conditionals|Смешанные условные", "Wish / if only|Wish / if only", "Advanced passive|Сложные формы пассива", "Inversion|Инверсия", "Academic vocabulary|Академическая лексика", "Presentation skills|Навыки презентации"],
 "informatics": ["Kompýuter grafikasy|Компьютерная графика", "Rekursiýa|Рекурсия", "Maglumat gurluşlary|Структуры данных", "SQL|SQL", "Mobil programmalar|Мобильные приложения", "Şifrlemek|Шифрование"],
}
P[11] = {
 "turkmen": ["Tekst we onuň gurluşy|Текст и его структура", "Funksional stiller|Функциональные стили", "Çeper dil serişdeleri|Средства выразительности", "Terjime sungaty|Искусство перевода", "Gysgaltmalar|Сокращения", "Rezýume ýazmak|Пишем резюме"],
 "literature": ["Žýul Wern we ylmy fantastika|Жюль Верн и научная фантастика", "Çehow|Чехов", "Hemingueý|Хемингуэй", "Aýtmatow|Айтматов", "Markes|Маркес", "Häzirki zaman poeziýasy|Современная поэзия"],
 "math": ["Önüm|Производная", "Önümiň ulanylyşy|Применение производной", "Funksiýany derňemek|Исследование функции", "Başlangyç funksiýa|Первообразная", "Integral|Интеграл", "Integralyň ulanylyşy|Применение интеграла"],
 "geometry": ["Silindr|Цилиндр", "Konus|Конус", "Şar we sfera|Шар и сфера", "Jisimleriň göwrümi|Объёмы тел", "Giňişlikde koordinatalar|Координаты в пространстве", "Giňişlikde wektorlar|Векторы в пространстве"],
 "physics": ["Elektrostatika|Электростатика", "Kondensator|Конденсатор", "Hemişelik tok|Постоянный ток", "Magnit meýdany|Магнитное поле", "Elektromagnit induksiýa|Электромагнитная индукция", "Üýtgeýän tok|Переменный ток"],
 "chemistry": ["Aldegidler|Альдегиды", "Karbon kislotalary|Карбоновые кислоты", "Ýaglar|Жиры", "Uglewodlar|Углеводы", "Aminokislotalar we beloklar|Аминокислоты и белки", "Polimerler|Полимеры"],
 "biology": ["Adamyň genetikasy|Генетика человека", "Seleksiýa|Селекция", "Biotehnologiýa|Биотехнология", "Immunitet|Иммунитет", "Ýaşaýşyň döreýşi|Происхождение жизни", "Adamyň ewolýusiýasy|Эволюция человека"],
 "geography": ["Demografiýa|Демография", "Şäherleşme|Урбанизация", "Halkara söwda|Международная торговля", "Syýahatçylyk|Туризм", "Suw baýlyklary|Водные ресурсы", "Howanyň üýtgemegi|Изменение климата"],
 "history": ["XX asyryň ylmy açyşlary|Научные открытия XX века", "Sowuk uruş|Холодная война", "Kolonial ulgamyň dargamagy|Распад колониальной системы", "Ýewropa Bileleşigi|Европейский союз", "Aziýanyň ykdysady ösüşi|Экономический рост Азии", "Häzirki zaman dünýäsi|Современный мир"],
 "russian": ["Goşma sözlemiň sintaksisi|Синтаксис сложного предложения", "Punktuasiýa|Пунктуация", "Çeperçilik serişdeleri|Средства выразительности", "Publisistika|Публицистика", "Resenziýa|Рецензия", "Ekzamene taýýarlyk|Подготовка к экзамену"],
 "english": ["Tenses review|Повторение времён", "Cleft sentences|Эмфатические конструкции", "Reporting verbs|Глаголы косвенной речи", "Idioms|Идиомы", "Argumentative essay|Аргументативное эссе", "Job interview|Собеседование"],
 "informatics": ["Algoritmleriň derňewi|Анализ алгоритмов", "Graflar|Графы", "JavaScript|JavaScript", "Bulut tehnologiýalary|Облачные технологии", "Maşyn öwrenmek|Машинное обучение", "Maglumat etikasy|Этика данных"],
}
P[12] = {
 "turkmen": ["Diliň taryhy|История языка", "Gadymy türki ýazgylar|Древнетюркские надписи", "Häzirki diliň kadalary|Нормы современного языка", "Ylmy iş ýazmak|Научная работа", "Jedel we çykyş|Дебаты и выступление", "Gaýtalamak: sintaksis|Повторение: синтаксис"],
 "literature": ["Edebi akymlar|Литературные направления", "Postmodernizm|Постмодернизм", "Nobel baýragynyň eýeleri|Нобелевские лауреаты", "Häzirki türkmen edebiýaty|Современная туркменская литература", "Edebiýat we kino|Литература и кино", "Edebi esse|Литературное эссе"],
 "math": ["Kompleks sanlar|Комплексные числа", "Matematiki induksiýa|Математическая индукция", "Ähtimallyk nazaryýeti|Теория вероятностей", "Statistika|Статистика", "Matrisalar|Матрицы", "Gaýtalamak: funksiýalar|Повторение: функции"],
 "geometry": ["Üstüň meýdany|Площадь поверхности", "Aýlanma jisimleri|Тела вращения", "Simmetriýa|Симметрия", "Geometrik öwrülişikler|Геометрические преобразования", "Giňişlik meseleleri|Пространственные задачи", "Gaýtalamak: geometriýa|Повторение: геометрия"],
 "physics": ["Optika|Оптика", "Ýagtylygyň tolkun häsiýetleri|Волновые свойства света", "Otnositellik nazaryýeti|Теория относительности", "Kwant fizikasy|Квантовая физика", "Atom ýadrosy|Атомное ядро", "Astrofizika|Астрофизика"],
 "chemistry": ["Metallar|Металлы", "Metal däller|Неметаллы", "Elektroliz|Электролиз", "Himiki kinetika|Химическая кинетика", "Himiki deňagramlylyk|Химическое равновесие", "Himiýa we ekologiýa|Химия и экология"],
 "biology": ["Ekologiýanyň kanunlary|Законы экологии", "Populýasiýalar|Популяции", "Biologik dürlülik|Биоразнообразие", "Adam we biosfera|Человек и биосфера", "Neýrobiologiýa|Нейробиология", "Gaýtalamak: biologiýa|Повторение: биология"],
 "geography": ["Geografik maglumat ulgamlary|Геоинформационные системы", "Ýeri kosmosdan öwrenmek|Изучение Земли из космоса", "Durnukly ösüş|Устойчивое развитие", "Tebigy betbagtçylyklar|Стихийные бедствия", "Ýeriň geologik taryhy|Геологическая история Земли", "Gaýtalamak: geografiýa|Повторение: география"],
 "history": ["Taryh ylmynyň usullary|Методы исторической науки", "Arheologiýa|Археология", "Altyndepe we Margiana|Алтын-депе и Маргиана", "Tehnologiýalaryň taryhy|История технологий", "UNESKO-nyň dünýä mirasy|Всемирное наследие ЮНЕСКО", "Gaýtalamak: taryh|Повторение: история"],
 "russian": ["Diliň kadalary|Нормы русского языка", "Orfoepiýa|Орфоэпия", "Resmi-iş stili|Официально-деловой стиль", "Argumentasiýa|Аргументация", "Teksti derňemek|Анализ текста", "Gaýtalamak|Повторение"],
 "english": ["Academic writing|Академическое письмо", "Citing sources|Ссылки на источники", "Debate language|Язык дебатов", "Literature in English|Литература на английском", "Business English|Деловой английский", "Exam strategies|Стратегии экзамена"],
 "informatics": ["Programmirleme taslamasy|Программный проект", "Kiberhowpsuzlyk: çuňňur|Кибербезопасность: углублённо", "Blokçeýn|Блокчейн", "Neýron torlar|Нейронные сети", "IT hünärleri|IT-профессии", "Gaýtalamak: informatika|Повторение: информатика"],
}

out = {g: {s: [{"tk": t.split("|")[0], "ru": t.split("|")[1]} for t in ts] for s, ts in subj.items()} for g, subj in P.items()}
json.dump(out, open(__file__.replace("plan.py", "plan.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
print(sum(len(ts) for s in P.values() for ts in s.values()), "topics,", sum(len(s) for s in P.values()), "grade-subject pairs")
