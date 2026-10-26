import '../models/audit_result.dart';
import '../models/diagnostic.dart';

/// Escapes text for use in HTML element content and quoted attributes.
String escapeHtml(String text) {
  final buffer = StringBuffer();
  for (final rune in text.runes) {
    switch (rune) {
      case 0x26:
        buffer.write('&amp;');
      case 0x3C:
        buffer.write('&lt;');
      case 0x3E:
        buffer.write('&gt;');
      case 0x22:
        buffer.write('&quot;');
      case 0x27:
        buffer.write('&#39;');
      case 0x60:
        buffer.write('&#96;');
      default:
        buffer.writeCharCode(rune);
    }
  }
  return buffer.toString();
}

/// Renders a self-contained HTML report: no external fonts, scripts or
/// images. All project-derived text is escaped with [escapeHtml].
class HtmlReporter {
  const HtmlReporter();

  String render(AuditResult result) {
    final e = escapeHtml;
    final status = result.passed ? 'Passed' : 'Failed';
    final codes = {for (final d in result.diagnostics) d.code}.toList()
      ..sort((a, b) => a.id.compareTo(b.id));

    final out = StringBuffer()
      ..writeln('<!doctype html>')
      ..writeln('<html lang="en">')
      ..writeln('<head>')
      ..writeln('<meta charset="utf-8">')
      ..writeln(
        '<meta name="viewport" content="width=device-width, initial-scale=1">',
      )
      ..writeln('<title>Localization Doctor report</title>')
      ..writeln('<style>$_css</style>')
      ..writeln('</head>')
      ..writeln('<body>')
      ..writeln('<main>')
      ..writeln('<header>')
      ..writeln('<h1>Localization Doctor report</h1>')
      ..writeln(
        '<p class="meta">Project <code>${e(result.projectPath)}</code> · '
        'version ${e(result.toolVersion)} · generated '
        '${e(result.generatedAt.toUtc().toIso8601String())}</p>',
      )
      ..writeln(
        '<p class="status ${result.passed ? 'pass' : 'fail'}" role="status">'
        '$status — ${result.violations.length} violation(s) at or above '
        '“${e(result.failOn.name)}”</p>',
      )
      ..writeln('</header>')
      ..writeln('<section class="cards" aria-label="Summary">')
      ..writeln(_card('Errors', result.count(Severity.error), 'error'))
      ..writeln(_card('Warnings', result.count(Severity.warning), 'warning'))
      ..writeln(_card('Info', result.count(Severity.info), 'info'))
      ..writeln(_card('Suppressed', result.suppressedCount, 'muted'))
      ..writeln('</section>');

    out.writeln('<section><h2>Locale coverage</h2>');
    if (result.coverage.isEmpty) {
      out.writeln('<p>No coverage data: no valid base locale was found.</p>');
    } else {
      out
        ..writeln('<div class="scroll"><table>')
        ..writeln(
          '<thead><tr><th scope="col">Bundle</th><th scope="col">Locale</th>'
          '<th scope="col" class="num">Total</th>'
          '<th scope="col" class="num">Translated</th>'
          '<th scope="col" class="num">Missing</th>'
          '<th scope="col" class="num">Empty</th>'
          '<th scope="col" class="num">Invalid</th>'
          '<th scope="col">Coverage</th></tr></thead><tbody>',
        );
      for (final c in result.coverage) {
        final tag = c.isBase
            ? ' <span class="tag">base</span>'
            : c.isOptional
            ? ' <span class="tag">optional</span>'
            : '';
        final invalidTag = c.fileValid
            ? ''
            : ' <span class="tag">invalid file</span>';
        out.writeln(
          '<tr><td><code>${e(c.bundle)}</code></td>'
          '<td>${e(c.locale)}$tag$invalidTag</td>'
          '<td class="num">${c.total}</td>'
          '<td class="num">${c.translated}</td>'
          '<td class="num">${c.missing}</td>'
          '<td class="num">${c.empty}</td>'
          '<td class="num">${c.invalid}</td>'
          '<td><div class="bar" role="img" aria-label="${c.percent}% '
          'translated"><span style="width:${c.percent}%"></span></div>'
          '<span class="pct">${c.percent}%</span></td></tr>',
        );
      }
      out.writeln('</tbody></table></div>');
    }
    out.writeln('</section>');

    out
      ..writeln('<section><h2>Diagnostics</h2>')
      ..writeln('<form class="filters" onsubmit="return false">')
      ..writeln(
        '<label>Search <input id="q" type="search" '
        'placeholder="key, file, message…"></label>',
      )
      ..writeln(
        '<label>Severity <select id="sev">'
        '<option value="">All</option><option value="error">Errors</option>'
        '<option value="warning">Warnings</option>'
        '<option value="info">Info</option></select></label>',
      )
      ..write('<label>Check <select id="code"><option value="">All</option>');
    for (final code in codes) {
      out.write(
        '<option value="${code.id}">${code.id} — ${e(code.title)}</option>',
      );
    }
    out
      ..writeln('</select></label>')
      ..writeln('<span id="count" aria-live="polite"></span>')
      ..writeln('</form>');

    if (result.diagnostics.isEmpty) {
      out.writeln('<p class="empty">No localization problems found.</p>');
    } else {
      out
        ..writeln('<div class="scroll"><table id="diagnostics">')
        ..writeln(
          '<thead><tr><th scope="col">Severity</th><th scope="col">Code</th>'
          '<th scope="col">Location</th><th scope="col">Details</th>'
          '</tr></thead><tbody>',
        );
      for (final d in result.diagnostics) {
        final search = [
          d.code.id,
          d.message,
          d.key ?? '',
          d.locale ?? '',
          d.location?.toString() ?? '',
          d.bundle ?? '',
        ].join(' ').toLowerCase();
        out.writeln(
          '<tr data-severity="${d.severity.name}" data-code="${d.code.id}" '
          'data-search="${e(search)}">'
          '<td><span class="sev ${d.severity.name}">${d.severity.name}</span>'
          '${d.confidence == Confidence.definite ? '' : '<br><small>${d.confidence.name}</small>'}'
          '</td>'
          '<td><abbr title="${e(d.code.title)}">${d.code.id}</abbr></td>'
          '<td><code>${e(d.location?.toString() ?? d.bundle ?? '—')}</code>'
          '${d.locale == null ? '' : '<br><small>locale ${e(d.locale!)}</small>'}'
          '</td>'
          '<td>${e(d.message)}'
          '${d.suggestion == null ? '' : '<div class="fix">Fix: ${e(d.suggestion!)}</div>'}'
          '${d.relatedLocations.isEmpty ? '' : '<div class="related">See also: ${d.relatedLocations.map((l) => '<code>${e(l.toString())}</code>').join(', ')}</div>'}'
          '</td></tr>',
        );
      }
      out.writeln('</tbody></table></div>');
    }
    out.writeln('</section>');

    if (result.skippedFiles.isNotEmpty) {
      out.writeln('<section><h2>Skipped files</h2><ul>');
      for (final f in result.skippedFiles) {
        out.writeln('<li><code>${e(f)}</code></li>');
      }
      out.writeln('</ul></section>');
    }

    out
      ..writeln('</main>')
      ..writeln('<script>$_script</script>')
      ..writeln('</body>')
      ..writeln('</html>');
    return out.toString();
  }

  String _card(String label, int value, String kind) =>
      '<div class="card $kind"><span class="value">$value</span>'
      '<span class="label">$label</span></div>';
}

const _css = '''
:root{--bg:#f7f7f8;--fg:#1d1d22;--muted:#5b5b66;--card:#fff;--border:#dcdce2;
--error:#b3261e;--warning:#8a5a00;--info:#0b57a4;--ok:#1e6b32;--bar:#2f6fde}
@media (prefers-color-scheme:dark){:root{--bg:#121216;--fg:#ececf1;--muted:#a9a9b6;
--card:#1c1c22;--border:#33333d;--error:#ff8a80;--warning:#ffc266;--info:#8ab8ff;
--ok:#7fd99a;--bar:#6f9cff}}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--fg);
font:15px/1.5 system-ui,-apple-system,"Segoe UI",Roboto,sans-serif}
main{max-width:1100px;margin:0 auto;padding:24px 16px 48px}
h1{font-size:1.6rem;margin:0 0 4px}h2{font-size:1.2rem;margin:32px 0 12px}
.meta{color:var(--muted);margin:0 0 12px;overflow-wrap:anywhere}
code{font-family:ui-monospace,SFMono-Regular,Consolas,monospace;font-size:.9em;
overflow-wrap:anywhere}
.status{display:inline-block;padding:6px 14px;border-radius:999px;font-weight:600;
margin:0;border:1px solid currentColor}
.status.pass{color:var(--ok)}.status.fail{color:var(--error)}
.cards{display:grid;grid-template-columns:repeat(auto-fit,minmax(130px,1fr));gap:12px;
margin-top:20px}
.card{background:var(--card);border:1px solid var(--border);border-radius:10px;
padding:12px 16px;display:flex;flex-direction:column}
.card .value{font-size:1.6rem;font-weight:700}.card .label{color:var(--muted)}
.card.error .value{color:var(--error)}.card.warning .value{color:var(--warning)}
.card.info .value{color:var(--info)}
.scroll{overflow-x:auto;border:1px solid var(--border);border-radius:10px;
background:var(--card)}
table{border-collapse:collapse;width:100%}
th,td{text-align:left;padding:8px 12px;border-bottom:1px solid var(--border);
vertical-align:top}
th{font-size:.85rem;color:var(--muted);font-weight:600}
tr:last-child td{border-bottom:0}
.num{text-align:right;font-variant-numeric:tabular-nums}
.bar{display:inline-block;width:90px;height:8px;border-radius:4px;
background:var(--border);vertical-align:middle;margin-right:8px;overflow:hidden}
.bar span{display:block;height:100%;background:var(--bar)}
.pct{font-variant-numeric:tabular-nums}
.tag{font-size:.75rem;border:1px solid var(--border);border-radius:4px;padding:0 4px;
color:var(--muted)}
.sev{font-weight:600;text-transform:uppercase;font-size:.8rem}
.sev.error{color:var(--error)}.sev.warning{color:var(--warning)}.sev.info{color:var(--info)}
#diagnostics td:nth-child(3){min-width:220px}
.fix{color:var(--muted);margin-top:4px}.related{color:var(--muted);font-size:.85rem}
.filters{display:flex;flex-wrap:wrap;gap:12px;align-items:end;margin-bottom:12px}
.filters label{display:flex;flex-direction:column;font-size:.85rem;color:var(--muted)}
input,select{font:inherit;color:var(--fg);background:var(--card);
border:1px solid var(--border);border-radius:6px;padding:6px 8px;min-width:180px}
input:focus,select:focus{outline:2px solid var(--bar);outline-offset:1px}
#count{color:var(--muted);font-size:.85rem}
.empty{color:var(--ok)}
''';

const _script = '''
(function(){
var q=document.getElementById('q'),sev=document.getElementById('sev'),
code=document.getElementById('code'),count=document.getElementById('count');
var rows=Array.prototype.slice.call(document.querySelectorAll('#diagnostics tbody tr'));
function apply(){var text=q.value.trim().toLowerCase(),s=sev.value,c=code.value,shown=0;
rows.forEach(function(r){var ok=(!s||r.dataset.severity===s)&&(!c||r.dataset.code===c)&&
(!text||r.dataset.search.indexOf(text)!==-1);r.hidden=!ok;if(ok)shown++;});
count.textContent=shown+' of '+rows.length+' shown';}
[q,sev,code].forEach(function(el){el.addEventListener('input',apply);});apply();})();
''';
