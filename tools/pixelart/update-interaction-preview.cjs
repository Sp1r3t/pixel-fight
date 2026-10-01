const fs=require('fs'),path=require('path');
const file=path.resolve(__dirname,'../../art/sprites/rework/new-skins/preview.html');
let html=fs.readFileSync(file,'utf8');
html=html.replace("Super:'Ульта'}","Super:'Ульта',Pulled:'Притягивание',Grabbed:'В захвате',Lifted:'Подъём жертвы',Thrown:'Жертву бросают',Launched:'Подбрасывание',Slammed:'Удар о землю',Bound:'Сковывание',Suspended:'Зависание'}");
html=html.replace("['motion','defense','combat','situational','recovery','super']","['motion','defense','combat','situational','recovery','super','reactions-grab','reactions-control']");
html=html.replace('из 6 листов','из 8 листов').replace(' · ещё рисуется',' · кадры пока отсутствуют');
fs.writeFileSync(file,html);
