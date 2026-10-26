"""Renders a synthetic SBI statement (text fixture) into a password-protected PDF.

Usage: python tool/make_statement_pdf.py <fixture-name a|b|c> <out.pdf> [password]

The fixture text comes from test/fixtures/sbi_statements.dart (fake people, fake
numbers). Monospaced Courier keeps the column geometry of the original layout,
and the file is encrypted with RC4-128 (Standard handler V2 R3) — the scheme
the owner's real SBI e-statement uses — so the on-device path (PDFium open with
password -> positioned words -> table) is exercised end to end.
"""
import re
import sys

from pypdf import PdfReader, PdfWriter
from reportlab.lib.pagesizes import A4, landscape
from reportlab.pdfgen import canvas

which, out = sys.argv[1].lower(), sys.argv[2]
password = sys.argv[3] if len(sys.argv) > 3 else None
src = open('test/fixtures/sbi_statements.dart', encoding='utf-8').read()
name = {'a': 'sbiLayoutA', 'b': 'sbiLayoutB', 'c': 'sbiLayoutC'}[which]
text = re.search(name + r" = r'''\n(.*?)'''", src, re.S).group(1)

plain = out + '.plain.pdf'
c = canvas.Canvas(plain, pagesize=landscape(A4))
width, height = landscape(A4)
c.setFont('Courier', 7)
y = height - 30
for line in text.split('\n'):
    if y < 30:
        c.showPage()
        c.setFont('Courier', 7)
        y = height - 30
    c.drawString(20, y, line)
    y -= 9
c.save()

writer = PdfWriter(clone_from=PdfReader(plain))
if password:
    writer.encrypt(user_password=password, owner_password=None, algorithm='RC4-128')
with open(out, 'wb') as fh:
    writer.write(fh)
import os
os.remove(plain)
print('wrote', out, 'encrypted' if password else 'plain')
