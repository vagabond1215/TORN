import json
from pathlib import Path
from openpyxl import load_workbook

src = Path('AUG2026 Growth Contest.xlsx')
wb = load_workbook(src, data_only=False)

out = {
    'source': str(src),
    'sheetnames': wb.sheetnames,
    'sheets': []
}

for ws in wb.worksheets:
    sheet = {
        'title': ws.title,
        'max_row': ws.max_row,
        'max_column': ws.max_column,
        'merged_cells': [str(r) for r in ws.merged_cells.ranges],
        'freeze_panes': str(ws.freeze_panes) if ws.freeze_panes else None,
        'column_widths': {k: v.width for k, v in ws.column_dimensions.items() if v.width is not None},
        'row_heights': {str(k): v.height for k, v in ws.row_dimensions.items() if v.height is not None},
        'cells': []
    }
    for row in ws.iter_rows():
        for c in row:
            if c.value is not None:
                sheet['cells'].append({
                    'coord': c.coordinate,
                    'value': c.value,
                    'number_format': c.number_format,
                    'style_id': c.style_id,
                })
    out['sheets'].append(sheet)

Path('growth_workbook_snapshot.json').write_text(json.dumps(out, indent=2, default=str), encoding='utf-8')
print(json.dumps({'sheetnames': wb.sheetnames, 'summary': [(ws.title, ws.max_row, ws.max_column) for ws in wb.worksheets]}, indent=2))
