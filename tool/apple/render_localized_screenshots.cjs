// Keep approved compositions and order; replace UI captures and translated copy only.
const fs=require('node:fs/promises'),path=require('node:path'),assert=require('node:assert/strict');
const {pathToFileURL}=require('node:url'),{createHash}=require('node:crypto');
const {chromium}=require('playwright'),sharp=require('sharp');
const config=require('./store-screenshots.json'),captions=require('./store-cover-copy.json');
const root=path.resolve(__dirname,'../..'),output=path.resolve(process.env.STORE_OUTPUT||path.join(root,'output/app-store-screenshots'));
const sha=data=>createHash('sha256').update(data).digest('hex');
const sources={
 '01-upcoming-planner-light':['01-upcoming-planner','light'],'01-upcoming-planner-dark':['01-upcoming-planner','dark'],
 '02-focus-dark':['02-focus','dark'],'03-calendar-light':['03-calendar','light'],'03-calendar-dark':['03-calendar','dark'],
 '04-timeline-dark':['04-timeline','dark'],'05-priority-matrix-dark':['05-priority-matrix','dark'],'06-kanban-dark':['06-kanban','dark'],
 '08-habits-dark':['08-habits','dark'],'09-search-dark':['09-search','dark'],'10-reports-dark':['10-reports','dark'],
 'x-projects-dark':['11-projects-labels','dark'],'08-projects-labels-dark':['11-projects-labels','dark'],
 '03-today-01-sepia':['12-customization','sepia'],'03-today-02-blue':['12-customization','ocean'],
 '03-today-03-luna':['12-customization','graphite'],'03-today-04-forest':['12-customization','forest'],
};
const marketing='h1,.copy p,.eyebrow:not(.open-source),.open-source span,.feature,.theme-labels span,.theme-label,.calendar-themes span,.voice-step,.voice-note,.info-title,.info-copy,.description,.voice-caption,.themes span,.step,.payoff p,.payoff small,header p,figcaption';
async function renderWatch(browser, results) {
 const settings=config.devices.watch;
 for(const locale of(process.env.STORE_RENDER_LOCALES||config.locales.join(',')).split(',')){
  assert(config.locales.includes(locale));
  const language={'en-US':'en','de-DE':'de','es-ES':'es','fr-FR':'fr','ar-SA':'ar','zh-Hans':'zh','pt-BR':'pt'}[locale]||locale;
  const copy=JSON.parse(await fs.readFile(path.join(root,'apps/flutter/lib/ui/core/localization',`app_${language}.arb`),'utf8'));
  const uiLocale=process.env.STORE_UI_LOCALE==='localized'?locale:(process.env.STORE_UI_LOCALE||'en-US');
  const page=await browser.newPage({viewport:{width:416,height:496},deviceScaleFactor:1,reducedMotion:'reduce',locale});
  try{
   await page.route(/^https?:/,route=>route.abort());
   const folder=path.join(output,'watch',locale);await fs.mkdir(folder,{recursive:true});
   for(const[name,key]of[['01-voice-input','addTask'],['02-tasks','navToday'],['03-focus','navFocus']]){
    const source=path.join(output,'raw/watch',uiLocale,name+'.png'),data=await fs.readFile(source);
    const provenance=JSON.parse(await fs.readFile(source.replace(/\.png$/,'.json'),'utf8'));
    assert.equal(provenance.locale,uiLocale);assert.equal(provenance.device,'watch');assert(provenance.texts.length);
    await page.goto(pathToFileURL(path.join(__dirname,'templates/watch/template.html')).href);
    const text=await page.evaluate(({title,source,locale})=>{
     document.documentElement.lang=locale;
     const heading=document.querySelector('h1'),caption=document.querySelector('.copy');heading.textContent=title;
     caption.style.top='18px';caption.style.direction=locale==='ar-SA'?'rtl':'ltr';caption.style.textAlign=locale==='ar-SA'?'right':'left';
     const image=document.querySelector('img');image.src=source;
     image.style.cssText='display:block;position:relative;inset:auto;width:100%;height:auto;object-fit:contain';
     let size=40;const screen=document.querySelector('.screen-shell').getBoundingClientRect();
     while(size>=22){heading.style.fontSize=size+'px';if(heading.scrollWidth<=heading.clientWidth+1&&caption.getBoundingClientRect().bottom<=screen.top-4)break;size--;}
     if(size<22)throw Error('Watch caption overflow: '+title);
     return {title,fontSize:size};
    },{title:copy[key],source:pathToFileURL(source).href,locale});
    await page.evaluate(async()=>{await document.fonts.ready;await document.querySelector('img').decode();});
    const file=path.join(folder,name+'.png');
    await sharp(await page.screenshot({animations:'disabled'})).resize(...settings.output).flatten({background:'#df382f'}).removeAlpha().withIccProfile('srgb').png().toFile(file);
    results.push({device:'watch',locale,uiLocale,file:path.relative(output,file),source:path.relative(output,source),sourceSha256:sha(data),sha256:sha(await fs.readFile(file)),text});
   }
  }finally{await page.close();}
 }
}
(async()=>{
 assert.deepEqual(new Set(Object.keys(captions.locales)),new Set(config.locales));
 for(const [locale,values]of Object.entries(captions.locales))assert.equal(values.length,captions.source.length,locale);
 await fs.mkdir(output,{recursive:true});await fs.cp(path.join(__dirname,'templates/assets'),path.join(output,'art'),{recursive:true});
 const browser=await chromium.launch({headless:true,args:['--allow-file-access-from-files']}),results=[];
 try{
  for(const device of(process.env.STORE_RENDER_DEVICES||'iphone').split(',')){
   if(device==='watch'){await renderWatch(browser,results);continue;}
   const settings=config.devices[device],deck=config.decks[device];assert(settings&&deck,device);assert.equal(deck.length,10);
   const[width,height]=settings.canvas;
   for(const locale of(process.env.STORE_RENDER_LOCALES||config.locales.join(',')).split(',')){
    assert(config.locales.includes(locale));
    const uiLocale=process.env.STORE_UI_LOCALE==='localized'?locale:(process.env.STORE_UI_LOCALE||'en-US');
    const page=await browser.newPage({viewport:{width,height},deviceScaleFactor:1,reducedMotion:'reduce',locale}),loaded=new Map();
    await page.route(/^https?:/,route=>route.abort());
    try{
     const folder=path.join(output,device,locale);await fs.mkdir(folder,{recursive:true});
     for(const[name,layout]of deck){
      loaded.clear();const[filename,query]=layout.split('?'),template=path.join(__dirname,'templates',settings.template,filename);
      await page.goto(pathToFileURL(template).href+(query?'?'+query:''));
      const replacements={};
      for(const src of await page.evaluate(()=>[...document.images].map(image=>image.src))){
       const key=path.basename(new URL(src).pathname).replace(/\.(png|PNG)$/,'');
       if(!sources[key]){
        assert(src.includes('/assets/'),'Unmapped image: '+src);
        const art=path.join(output,'art',path.basename(new URL(src).pathname));
        loaded.set(art,await fs.readFile(art));continue;
       }
       const[capture,theme]=sources[key],source=path.join(output,'raw',device,uiLocale,theme,capture+'.png'),data=await fs.readFile(source);
       const provenance=JSON.parse(await fs.readFile(source.replace(/\.png$/,'.json'),'utf8'));
       assert.equal(provenance.locale,uiLocale);assert.equal(provenance.theme,theme);assert(provenance.texts.length,source);
       loaded.set(source,data);
       let imageSource=source;
       if(provenance.crop){
        assert.equal(capture,'09-search');assert(device!=='iphone');
        imageSource=source.replace(/\.png$/,'-palette.png');
        await sharp(data).extract(provenance.crop).png().toFile(imageSource);
       }
       replacements[src]={src:pathToFileURL(imageSource).href,cropped:!!provenance.crop};
      }
      await page.evaluate(replacements=>{for(const image of document.images){
       const replacement=replacements[image.src];if(!replacement)continue;image.src=replacement.src;
       if(replacement.cropped)Object.assign(image.style,{width:'100%',height:'100%',left:'0',top:'0',objectFit:'contain'});
      }},replacements);
      await page.evaluate(async()=>{await document.fonts.ready;await Promise.all([...document.images].map(i=>i.decode()));});
      const text=await page.evaluate(({marketing,source,values,locale,width,height})=>{
       document.documentElement.lang=locale;
       const normalize=value=>value.replace(/\s+/g,' ').trim().replace(/^0?\d+\s+/,'').toLowerCase();
       const dictionary=new Map(source.map((key,index)=>[normalize(key),values[index]])),measurements=[];
       for(const node of document.querySelectorAll(marketing)){
        if(!node.getClientRects().length||getComputedStyle(node).display==='none')continue;
        const style=getComputedStyle(node);
        // The original renderer fits explicit headline lines before translating them.
        if(node.tagName==='H1'){
         const lines=node.innerText.split('\n'),ctx=document.createElement('canvas').getContext('2d');
         const maxWidth=Math.min(node.getBoundingClientRect().width,width-node.getBoundingClientRect().x-80);
         let size=parseFloat(style.fontSize);
         const fits=()=>{ctx.font=`${style.fontWeight} ${size}px ${style.fontFamily}`;return lines.every(line=>ctx.measureText(line).width<=maxWidth);};
         while(!fits()&&size>24){size-=2;node.style.fontSize=size+'px';}
        }
        const before=node.getBoundingClientRect(),original=node.innerText.trim(),key=normalize(original);
        const currentKey=key==='blue'?'ocean':key==='luna'?'graphite':key,translated=dictionary.get(currentKey);
        if(!translated)throw Error('Missing original marketing caption: '+original);
        if(locale!=='en-US'||currentKey!==key){
         const index=node.querySelector('.index')||(node.matches('.step')?node.querySelector('span'):null);
         if(index){for(const child of[...node.childNodes])if(child!==index)child.remove();node.append(' '+translated);}else node.textContent=translated;
         if(locale==='ar-SA'){node.style.direction='rtl';node.style.textAlign='right';}
         if(node.tagName==='H1')node.style.whiteSpace='normal';
         if(!node.matches('.theme-label,.eyebrow,.open-source span,.themes span,.theme-labels span,.calendar-themes span'))node.style.maxWidth=before.width+'px';
         let size=parseFloat(style.fontSize);const minimum=Math.min(22,size/2);
         while(size>minimum){const box=node.getBoundingClientRect();if(node.scrollWidth<=node.clientWidth+1&&box.height<=before.height+2&&box.right<=width+1)break;node.style.fontSize=--size+'px';}
        }
        const box=node.getBoundingClientRect();
        if(box.x<0||box.y<0||box.right>width+1||box.bottom>height+1||node.scrollWidth>node.clientWidth+2)throw Error('Marketing copy exceeds canvas: '+node.innerText+' '+JSON.stringify({box:box.toJSON(),scroll:node.scrollWidth,client:node.clientWidth}));
        measurements.push({text:node.innerText,x:box.x,y:box.y,width:box.width,height:box.height,fontSize:parseFloat(getComputedStyle(node).fontSize)});
       }
       for(const img of document.querySelectorAll('.screen img,.screen-clip img'))if(!img.src.includes('/assets/')&&getComputedStyle(img).objectFit==='fill'&&getComputedStyle(img).height!=='auto')img.style.objectFit='contain';
       return measurements;
      },{marketing,source:captions.source,values:captions.locales[locale],locale,width,height});
      await page.evaluate(()=>document.fonts.ready);const file=path.join(folder,name+'.png');
      await sharp(await page.screenshot({animations:'disabled'})).resize(...settings.output,{fit:'cover'}).flatten({background:'#df382f'}).removeAlpha().withIccProfile('srgb').png().toFile(file);
      const meta=await sharp(file).metadata();assert.equal(meta.width,settings.output[0]);assert.equal(meta.height,settings.output[1]);assert.equal(meta.hasAlpha,false);assert.equal(meta.space,'srgb');assert((await sharp(file).stats()).entropy>1);
      const used=[...loaded].map(([source,data])=>({file:path.relative(output,source),sha256:sha(data)}));
      assert(used.length,'No image provenance: '+name);
      results.push({device,locale,uiLocale,file:path.relative(output,file),layout,templateSha256:sha(await fs.readFile(template)),source:used[0].file,sourceSha256:used[0].sha256,sources:used,sha256:sha(await fs.readFile(file)),text});
     }
     console.log(`${device}/${locale}: original ten compositions and order preserved`);
    }finally{await page.close();}
   }
  }
  assert.equal(new Set(results.map(row=>row.sha256)).size,results.length);
  await fs.writeFile(path.join(output,'render-checks.json'),JSON.stringify({browser:browser.version(),sharp:sharp.versions.sharp,results},null,2)+'\n');
  console.log(`PASS: ${results.length} opaque covers from original compositions`);
 }finally{await browser.close();}
})().catch(error=>{console.error(error);process.exitCode=1;});
