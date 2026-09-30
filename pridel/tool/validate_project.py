from pathlib import Path
import re, sys

ROOT = Path(__file__).resolve().parents[1]
errors=[]
required=[
 'lib/screens/onboarding_screen.dart','lib/screens/home_dashboard_screen.dart','lib/screens/history_screen.dart',
 'lib/screens/backup_screen.dart','lib/screens/diagnostics_screen.dart','lib/screens/cooking_mode_screen.dart',
 'lib/screens/pantry_screen.dart','lib/screens/shopping_screen.dart','lib/screens/recipes_screen.dart',
 'lib/data/app_database.dart','lib/controllers/app_controller.dart'
]
for f in required:
    if not (ROOT/f).exists(): errors.append(f'chýba {f}')

# Relative import integrity.
for p in (ROOT/'lib').rglob('*.dart'):
    text=p.read_text(encoding='utf-8')
    for m in re.finditer(r"import\s+'([^']+)'", text):
        rel=m.group(1)
        if rel.startswith('.') and not (p.parent/rel).resolve().exists(): errors.append(f'{p.relative_to(ROOT)}: neplatný import {rel}')

# Lightweight lexical bracket balance while ignoring strings/comments.
def balance(path):
    text=path.read_text(encoding='utf-8'); stack=[]; i=0; line=1; quote=None; triple=False; line_comment=False; block=0
    pairs={')':'(',']':'[','}':'{'}
    while i<len(text):
        c=text[i]; n=text[i+1] if i+1<len(text) else ''
        if c=='\n': line+=1; line_comment=False
        if line_comment: i+=1; continue
        if block:
            if c=='/' and n=='*': block+=1; i+=2; continue
            if c=='*' and n=='/': block-=1; i+=2; continue
            i+=1; continue
        if quote:
            if c=='\\': i+=2; continue
            if triple and text.startswith(quote*3,i): quote=None; triple=False; i+=3; continue
            if not triple and c==quote: quote=None; i+=1; continue
            i+=1; continue
        if c=='/' and n=='/': line_comment=True; i+=2; continue
        if c=='/' and n=='*': block=1; i+=2; continue
        if c in "'\"":
            if text.startswith(c*3,i): quote=c; triple=True; i+=3; continue
            quote=c; i+=1; continue
        if c in '([{': stack.append((c,line))
        elif c in ')]}':
            if not stack or stack[-1][0]!=pairs[c]: return f'riadok {line}: nesprávna zátvorka {c}'
            stack.pop()
        i+=1
    if stack: return f'neuzavreté zátvorky {stack[-5:]}'
for p in (ROOT/'lib').rglob('*.dart'):
    e=balance(p)
    if e: errors.append(f'{p.relative_to(ROOT)}: {e}')

checks={
 'lib/data/app_database.dart':['schemaVersion = 5','location TEXT','alert_dismissals','exportBackupJson','importBackupJson','getStorageSummary','getInAppAlertsEnabled'],
 'lib/screens/onboarding_screen.dart':['Využívať zásoby','Ako ďaleko plánovať','Upozornenia v aplikácii'],
 'lib/screens/pantry_screen.dart':['Chladnička','Špajza','Mraznička','Rýchlo pridať'],
 'lib/screens/home_dashboard_screen.dart':['Upozornenia','Uvariť zo zásob','História'],
 'lib/screens/recipes_screen.dart':['Zo zásob','Do 30 min','Nedávno'],
 'lib/screens/shopping_screen.dart':['Skopírovať / zdieľať zoznam'],
 'lib/screens/cooking_mode_screen.dart':['Režim varenia'],
}
for f,needles in checks.items():
    text=(ROOT/f).read_text(encoding='utf-8')
    for n in needles:
        if n not in text: errors.append(f'{f}: chýba kontrolný prvok {n!r}')

all_text='\n'.join(p.read_text(encoding='utf-8') for p in (ROOT/'lib').rglob('*.dart'))
if 'WebView' in all_text or 'webview' in all_text.lower(): errors.append('Flutter jadro nesmie znovu používať WebView.')
if 'http://' in all_text: errors.append('Nájdený nezabezpečený http:// odkaz v zdrojovom kóde.')

if errors:
    print('PROJECT CHECK FAILED')
    for e in errors: print('-',e)
    sys.exit(1)
print('PROJECT CHECK OK')
print('required files:',len(required))
