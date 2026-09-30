#!/usr/bin/env python3
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
recipes = json.loads((ROOT / 'assets/data/recipes.json').read_text(encoding='utf-8'))
ingredients = json.loads((ROOT / 'assets/data/ingredients.json').read_text(encoding='utf-8'))

def norm(unit):
    value = str(unit or '').strip().lower().replace('.', '')
    return {'gr':'g','kus':'ks','kusy':'ks','pc':'ks','pcs':'ks'}.get(value, value or 'g')

def dim(unit):
    value = norm(unit)
    if value in {'g','kg'}: return 'mass'
    if value in {'ml','l'}: return 'volume'
    if value == 'ks': return 'count'
    return 'custom:' + value

assert len(recipes) >= 170, f'Príliš málo receptov: {len(recipes)}'
assert len(ingredients) >= 170, f'Príliš málo surovín: {len(ingredients)}'
ids = set()
for recipe in recipes:
    rid = str(recipe.get('id', '')).strip()
    assert rid and rid not in ids, f'Duplicitné/neplatné ID: {rid}'
    ids.add(rid)
    assert str(recipe.get('name','')).strip(), f'{rid}: chýba názov'
    assert float(recipe.get('adult_kcal') or 0) > 0, f'{rid}: chýba adult_kcal'
    assert float(recipe.get('child_kcal') or 0) > 0, f'{rid}: chýba child_kcal'
    assert recipe.get('ingredients'), f'{rid}: recept bez surovín'
    assert not str(recipe.get('source_url') or '').strip(), f'{rid}: source_url nesmie byť zabalené v produkčných dátach'
    for item in recipe['ingredients']:
        name = item.get('ingredient')
        assert name in ingredients, f'{rid}: chýba definícia suroviny {name}'
        assert dim(item.get('unit')) == dim(ingredients[name].get('unit')), f'{rid}/{name}: nekompatibilná jednotka'
        assert float(item.get('adult_qty') or 0) >= 0 and float(item.get('child_qty') or 0) >= 0, f'{rid}/{name}: záporné množstvo'

for name, definition in ingredients.items():
    if definition.get('buy', True):
        assert float(definition.get('pack') or 0) > 0, f'{name}: chýba veľkosť balenia'
        assert float(definition.get('pack_price') or 0) > 0, f'{name}: chýba orientačná cena'

print(f'OK: {len(recipes)} receptov, {len(ingredients)} surovín')
