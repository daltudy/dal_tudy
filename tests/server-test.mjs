import fs from 'fs'
const cfg = fs.readFileSync('config.js','utf8'); const url = cfg.match(/url: '([^']+)'/)[1], key = cfg.match(/key: '([^']+)'/)[1]
const rpc = async (fn, a) => { const r = await fetch(`${url}/rest/v1/rpc/${fn}`, {method:'POST', headers:{apikey:key,'Content-Type':'application/json'}, body:JSON.stringify(a)}); const t = await r.text(); return {status:r.status, body:t?JSON.parse(t):null} }
const N = 'zz서버테스트', ok = (c, m) => { console.log((c?'PASS ':'FAIL ')+m); if(!c) process.exitCode = 1 }
let r = await rpc('ping', {}); ok(r.status===200 && r.body===1, 'ping '+JSON.stringify(r))
r = await rpc('st_login', {p_name:N, p_pin:'0000', p_create:false})
if (r.body.error === 'not_found') { r = await rpc('st_login', {p_name:N, p_pin:'0000', p_create:true}); ok(r.body.ok && r.body.created, 'create account') }
else ok(r.body.ok, 'login existing '+JSON.stringify(r.body))
const rev = r.body.rev
r = await rpc('st_save', {p_name:N, p_pin:'0000', p_data:{next:5, srs:{"1":{s:1,due:20800,w:0,c:1,last:1}}, log:{}, results:{}, wb:{}}, p_rev:rev}); ok(r.body.ok && r.body.rev===rev+1, 'save '+JSON.stringify(r.body))
r = await rpc('st_login', {p_name:N, p_pin:'0000', p_create:false}); ok(r.body.ok && r.body.data.next===5 && r.body.rev===rev+1, 'reload saved data next='+r.body.data?.next)
r = await rpc('st_save', {p_name:N, p_pin:'0000', p_data:{next:1}, p_rev:rev}); ok(r.body.error==='conflict' && r.body.data.next===5, 'stale save rejected as conflict')
r = await rpc('st_login', {p_name:N, p_pin:'9999', p_create:false}); ok(r.body.error==='wrong_pin', 'wrong pin rejected')
r = await rpc('st_login', {p_name:N, p_pin:'0000', p_create:false}); ok(r.body.ok, 'correct pin works after one wrong try')
const direct = await fetch(`${url}/rest/v1/students?select=*`, {headers:{apikey:key}}); const dt = await direct.text()
ok(direct.status>=400 || dt==='[]', 'direct table read blocked ('+direct.status+' '+dt.slice(0,80)+')')
r = await rpc('_st_check', {p_name:N, p_pin:'0000'}); ok(r.status>=400, 'internal function blocked ('+r.status+')')
r = await rpc('admin_list', {p_pw:'not-the-password'}); ok(r.body.error==='wrong_pw', 'admin list needs password')
