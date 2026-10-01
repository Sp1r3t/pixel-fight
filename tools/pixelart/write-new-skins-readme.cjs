const fs=require('fs'),path=require('path');
const root=path.resolve(__dirname,'../../art/sprites/rework/new-skins');
const m=JSON.parse(fs.readFileSync(path.join(root,'manifest.json'))),chars=Object.values(m.characters);
const panels=chars.reduce((n,c)=>n+c.frameCount/16,0),full=chars.filter(c=>c.frameCount===128).map(c=>c.id);
const supers=chars.filter(c=>c.panels.super?.file).map(c=>c.id);
const reactions=chars.filter(c=>c.panels['reactions-grab']?.file&&c.panels['reactions-control']?.file).map(c=>c.id);
const checkpoint=JSON.parse(fs.readFileSync(path.join(root,'generation-status.json')));
const blocked=checkpoint.status==='blocked-usage-limit' ? '\nГенерация остановлена лимитом встроенного сервиса изображений. По ответу сервиса сброс: **1 октября 2026, 21:15:09 по Москве**. Следующие недостающие панели: Byte recovery и Morrow motion. Сохранённые файлы повторно генерировать не требуется.\n' : '';
fs.writeFileSync(path.join(root,'README.md'),`# Анимации новых утверждённых скинов

Подготовлено **${panels} из 288 панелей** для 16 персонажей и 20 боссов. Каждому нужны восемь страниц: шесть собственных анимаций и две страницы реакций на чужие приёмы. Статус обновляется при сборке.
${blocked}

- Полные черновые наборы: ${full.join(', ')||'пока отсутствуют'}.
- Панели ульт: ${supers.join(', ')}.
- Обе панели реакций: ${reactions.join(', ')||'пока отсутствуют'}.
- Ещё отсутствует ${m.pending.length} панелей; ${m.repairs.length} панелей отмечены для проверки обрезки.

## Просмотр и файлы

Запуск из корня проекта: \`node tools/pixelart/serve-new-skins.cjs\`; адрес просмотра: http://127.0.0.1:8136/new-skins/preview.html.

\`gifs/\` — отдельные состояния и комбо. \`packed/\` — страницы 1024×1024, 16 ячеек по 256×256, четыре колонки. Файлы \`<имя>-<состояние>.png\` — оригинальные панели встроенного генератора изображений. \`manifest.json\` хранит исходные границы кадров и предупреждения. \`generation-status.json\` — список незавершённого.

## Взаимодействия

Для каждого бойца рисуются восемь реакций на его собственном скине: Pulled, Grabbed, Lifted, Thrown, Launched, Slammed, Bound, Suspended. Они занимают страницы 7 и 8. Вместе с двадцатью основными состояниями получается 28 состояний и 128 кадров на бойца.

Отдельная анимация жертвы используется в разных приёмах; точка зацепа, расстояние, высота, момент контакта и траектория задаются атакующим. Нужна проверка каждой пары с учётом размеров, крыльев, панциря, механических суставов и щупалец. Это не подтверждённая готовность всех пар к выпуску.

Brakk: крюк → притягивание → захват → подъём → бросок → удар о землю. В актуальной панели Brakk нет встроенного силуэта жертвы. Жертва должна отображаться отдельным спрайтом своего персонажа. Сценарии сохранены в \`interaction-plan.json\`, задания рисунков — \`reaction-prompts.json\`; собственные атаки и ульты — \`combat-prompts.json\`, \`panel-prompts.json\`, \`brakk-hook-prompt.md\`.

## Загрузка в Roblox

Картинки **ещё не загружены и не активированы в игре**. После визуальной проверки всех восьми страниц и парных сцен нужно загрузить восемь PNG на бойца, вписать полученные image asset ID в копию \`asset-ids.example.json\` и импортировать их через \`tools/pixelart/import-new-skins.cjs\`. Импорт принимает только проверенные наборы со статусом \`approved\`; менять статус до проверки нельзя. Подготовленный код выбирает реакции жертвы для постановок ульт и для попадания крюком.

\`*-source.png\` — ранние плотные раскадровки с неровной сеткой, не игровые атласы. \`rejected-packed/\`, \`rook-draft.png\`, \`brakk-super-v1.png\` и \`brakk-super-v2.png\` — предыдущие варианты. Текущая ульта Brakk — \`brakk-super.png\` (копия исправленного v3).
`);
console.log(JSON.stringify({panels,total:288,missing:m.pending.length,full,supers:supers.length,reactions:reactions.length}));
