# Практическое экзаменационное задание — Разработка проекта

Проект интерфейса программного продукта **PampGram** и интернет-страница
о нём.

## Структура папки

```
docs/exam-project/
├── README.md               ← этот файл (общая точка входа)
├── 01-target-audience.md   ← анализ целевой аудитории
├── 02-competitors.md       ← анализ 5 аналогичных продуктов
├── 03-wireframes.md        ← пояснительная записка к wireframe
├── 04-mockup.md            ← пояснительная записка к макету
├── site/                   ← готовая интернет-страница (пункт 5)
│   ├── index.html
│   ├── css/style.css
│   └── js/main.js
├── wireframes/             ← wireframe для desktop / tablet / mobile
│   └── wireframes.html
└── mockups/                ← экспортированные PDF-макеты (генерируются
                              при печати из браузера)
```

## Соответствие пунктам задания

| # | Требование | Где выполнено |
| --- | --- | --- |
| 1 | Анализ целевой аудитории | `01-target-audience.md` |
| 2 | Анализ 5 аналогичных продуктов + выводы | `02-competitors.md` |
| 3 | Wireframe (ПК, планшет, мобильное) → PDF | `wireframes/wireframes.html` (печать в PDF) |
| 4 | Макет (ПК, планшет, мобильное) → PDF | `site/index.html` + `04-mockup.md` (печать в PDF) |
| 5 | Интернет-страница о продукте (вёрстка) | `site/index.html`, `site/css/style.css`, `site/js/main.js` |

## Соответствие требованиям к интернет-странице (вёрстка)

| Требование | Где выполнено |
| --- | --- |
| Header (верхняя часть) | `<header class="site-header">` в `index.html` |
| Меню | `<nav id="site-nav">` в шапке |
| Основной контент | секции `#features`, `#catalog`, `#compare`, `#install`, `#subscribe`, `#faq` |
| Footer (нижняя часть) | `<footer class="site-footer">` |
| Flex-контейнеры | header, hero, adv-grid, cat-grid, install, subscribe, footer — все построены на `display: flex` / `flex-wrap: wrap` |
| Списки | `.site-nav__list`, `.hero__stats`, `.steps`, `.checks`, `.footer__nav ul` |
| Таблицы | секция `#compare` — `<table class="cmp">` |
| Формы | секция `#subscribe` — `<form class="form">` c input, select, checkbox, fieldset/legend, валидация |
| Текстовый + графический контент | текст в hero/секциях + SVG-логотип, SVG-иконка кнопки, макет телефона в hero, градиентные превью карточек, иконки-emoji |
| Hero-блок | секция `.hero` с заголовком, лидом, CTA, статистикой и mockup'ом |
| Каталог товаров | секция `#catalog` — карточки с фильтром «Все / Подарки / Ghost / UI» |
| Блок «преимущества компании» | секция `#features` — 4 карточки advantages |
| Дополнительные блоки | сравнение с конкурентами, шаги установки, форма подписки, FAQ, footer с 4 зонами |

## Как посмотреть

```bash
# просто открыть в браузере (без сервера)
open docs/exam-project/site/index.html
open docs/exam-project/wireframes/wireframes.html
```

Или запустить локальный статический сервер:

```bash
python3 -m http.server 8000 --directory docs/exam-project
# → http://localhost:8000/site/
```

## Как экспортировать в PDF (для демонстрации)

1. Открыть страницу в Chrome/Safari.
2. Включить DevTools → Device Mode → выбрать breakpoint
   (Desktop 1440 / iPad Air / iPhone 15).
3. Cmd/Ctrl + P → **Сохранить как PDF**.
4. Файл сохранить в `docs/exam-project/mockups/` с именами:
   - `mockup-desktop.pdf`
   - `mockup-tablet.pdf`
   - `mockup-mobile.pdf`
   - `wireframes.pdf`
