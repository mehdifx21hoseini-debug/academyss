# -*- coding: utf-8 -*-
import sys
sys.path.insert(0, "/tmp/claude-0/faces")
from build9 import panel, speed, tokens, CSS9

SEC = u"""
<section class="sec">
 <h2>%s</h2>
 %s
</section>"""

REMOVED = [
 ("چهار تب", "سه خانهٔ ریل — و LOG و STATS پنجرهٔ خودشان را باز می‌کنند",
  "چیزی که وسط ریپلی لمسش نمی‌کنید، نباید تمام‌مدت جا بگیرد"),
 ("دکمهٔ «Take the trade»", "حذف — خودِ BUY و SELL معاملهٔ خطوط را می‌گیرند",
  "سه راه برای یک کار، یعنی دو تا اضافه است"),
 ("نوار پیشرفت + «۳۷٪»", "یک خط ۲ پیکسلی زیر ساعت",
  "این یک واقعیت است، نه یک کنترل؛ پس شکل کنترل نداشته باشد"),
 ("پنج دکمهٔ سربرگ", "دو تا: کوچک‌کردن و بستن",
  "بقیه کلید دارند و در منوی راست‌کلیک هستند"),
 ("«۱٪ = ۴۸۷$ / ۰.۴۲ لات» به‌عنوان نوشته",
  "ریسک یک کنترل شد: ۰.۵ / ۱ / ۲ — لات خودش حساب می‌شود",
  "لحظهٔ آموزشی همین‌جاست: شاگرد ریسک را انتخاب می‌کند، ابزار حجم را"),
 ("«spread 1.4» در سطر خودش", "داخل نوار وضعیت",
  "یک عدد که روزی یک‌بار نگاهش می‌کنید، سطر نمی‌خواهد"),
]
ADDED = [
 ("قیمت، بزرگ", "رنگش جهت را می‌گوید",
  "ابزار ریپلی‌ای که قیمت روی پنلش نیست، شما را مجبور می‌کند جای دیگری را نگاه کنید"),
 ("اسلایدر سرعت، پیوسته از صفر",
  "«۱۲ تیک بر ثانیه · ۱.۰ ثانیه هر کندل» و کنارش «۱ ساعت در ۶۰ ثانیه»",
  "همان چیزی که خواستید: هم تیک، هم ثانیه — و سومی برای برنامه‌ریزی جلسه"),
 ("دقت تیک به‌عنوان کنترل جدا", "۱ / ۱۲ / ۱۰۰ تیک در هر کندل، درست زیر اسلایدر",
  "این نیمهٔ دیگر همان سؤال است، پس کنار همان می‌نشیند"),
 ("دو حالت به‌جای یک فرم", "بی‌پوزیشن: شکار — با پوزیشن: مدیریت",
  "پنل چیزی را نشان می‌دهد که همین حالا به آن نیاز دارید"),
 ("R به‌جای دلار", "‎+۱.۴ R اول، ‎+۶۸۲$ دوم",
  "بعد از بیست سال، هیچ‌کس معامله را با دلار قضاوت نمی‌کند"),
 ("نوار MAE / MFE", "چقدر بر خلافتان رفت، قبل از اینکه جواب بدهد",
  "چیزی که شاگرد هیچ‌وقت یادش نمی‌ماند و مربی همیشه می‌پرسد"),
]

def tbl(rows, h1, h2, h3):
    return ('<table><thead><tr><th>%s</th><th>%s</th><th>%s</th></tr></thead>'
            '<tbody>%s</tbody></table>'
            % (h1, h2, h3, "".join(
                "<tr><td class=x>%s</td><td class=y>%s</td><td class=z>%s</td></tr>"
                % r for r in rows)))

SPEEDS = "".join(
    '<figure class="sp"><figcaption>%s</figcaption>'
    '<div class="panel" style="%s;padding-bottom:9px">%s</div>'
    '<p>%s</p></figure>'
    % (lab, tokens(292), speed(pos, t, s, pl), fa)
    for lab, pos, t, s, pl, fa in (
      ("۰ — ایستاده", 0, "0", "&mdash;", "paused",
       "صفر یک نقطهٔ واقعی روی اسلایدر است و یعنی توقف. همان کنترلی که سرعت "
       "را می‌دهد، متوقف هم می‌کند."),
      ("مطالعه", 18, "3", "4.0", "1 h in 4 min",
       "برای وقتی که روی یک ستاپ خم شده‌اید و می‌خواهید کندل جلوی چشمتان ساخته شود."),
      ("جلسه", 46, "12", "1.0", "1 h in 60 s",
       "سرعت پیش‌فرض تمرین: یک ساعت بازار در یک دقیقه."),
      ("پویش", 88, "90", "0.13", "1 h in 8 s",
       "برای رد شدن از ساعت‌های مرده تا رسیدن به جایی که کار دارید.")))

HTML = u"""<title>Two-State Ticket</title>
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Archivo:wght@500;700&family=IBM+Plex+Mono:wght@400;500&family=Vazirmatn:wght@400;500;700&display=swap">
<style>
:root{--paper:#EDEEEF;--card:#FFFFFF;--ink:#15181A;--ink2:#4B5257;
 --ink3:#6F777C;--rule:#D4D8DB;--accent:#8A4A12;--accentink:#FFF;
 --fa:"Vazirmatn","Noto Sans Arabic",system-ui,sans-serif;
 --dis:"Archivo","Liberation Sans",sans-serif;
 --mono:"IBM Plex Mono","Liberation Mono",monospace}
:root:not([data-theme="light"]){@media (prefers-color-scheme:dark){
 --paper:#0E1012;--card:#171A1C;--ink:#E7EAEC;--ink2:#AAB2B7;--ink3:#838B90;
 --rule:#2A2F32;--accent:#E0863A;--accentink:#1B1E23}}
:root[data-theme="dark"]{--paper:#0E1012;--card:#171A1C;--ink:#E7EAEC;
 --ink2:#AAB2B7;--ink3:#838B90;--rule:#2A2F32;--accent:#E0863A;
 --accentink:#1B1E23}
*{box-sizing:border-box}
body{margin:0;background:var(--paper);color:var(--ink);font-family:var(--fa);
 font-size:15.5px;line-height:1.8}
.wrap{max-width:1080px;margin:0 auto;padding-inline:20px;padding-block:0}
header{padding-block:64px 30px}
.eyebrow{font-family:var(--mono);font-size:11px;letter-spacing:.18em;
 text-transform:uppercase;color:var(--accent);margin:0 0 14px}
h1{font-family:var(--dis);font-weight:700;font-size:clamp(30px,5.4vw,52px);
 line-height:1.14;margin:0 0 18px;text-wrap:balance}
.lede{margin:0;max-width:60ch;color:var(--ink2);font-size:17px}
.lede b{color:var(--ink);font-weight:500}
.sec{border-top:1px solid var(--rule);padding-block:34px 6px}
.sec h2{font-family:var(--dis);font-weight:500;font-size:24px;margin:0 0 18px}
.states{display:flex;gap:26px;flex-wrap:wrap;align-items:flex-start;
 margin-bottom:14px}
.st figcaption{font-family:var(--mono);font-size:11px;letter-spacing:.12em;
 text-transform:uppercase;color:var(--ink3);padding-bottom:10px}
.st p{max-width:30ch;color:var(--ink2);font-size:14px;margin:12px 0 0}
figure{margin:0}
.sp{margin-bottom:22px;max-width:340px}
.sp figcaption{font-size:14px;font-weight:500;padding-bottom:8px}
.sp p{margin:10px 0 0;color:var(--ink2);font-size:13.5px;line-height:1.7}
.spwrap{display:grid;grid-template-columns:repeat(auto-fit,minmax(300px,1fr));
 gap:8px 30px}
table{width:100%;border-collapse:collapse;margin-bottom:10px}
th{font-family:var(--mono);font-size:10px;letter-spacing:.12em;
 text-transform:uppercase;color:var(--ink3);text-align:right;
 padding:0 10px 8px;border-bottom:1px solid var(--rule);font-weight:400}
td{padding:11px 10px;border-bottom:1px solid var(--rule);vertical-align:top;
 font-size:14px}
td.x{color:var(--ink3);width:28%}
td.y{color:var(--ink);width:34%}
td.z{color:var(--ink2);width:38%}
.rule{background:var(--card);border:1px solid var(--rule);padding:20px 22px;
 margin-block:10px 4px}
.rule b{color:var(--accent)}
.note{color:var(--ink3);font-size:13.5px;max-width:62ch}
footer{border-top:1px solid var(--rule);padding-block:26px 66px;
 color:var(--ink3);font-size:13.5px;max-width:70ch}
@media (max-width:560px){.st p{max-width:none}}
__CSS9__
</style>
<div class="wrap">
<header>
 <p class="eyebrow">SS Replay &middot; Panel proposal</p>
 <h1>بلیت دوحالته</h1>
 <p class="lede">گفتید خیلی از چیزهای پنل به کارتان نمی‌آید. موافقم، و فکر می‌کنم دلیلش این است که پنل فعلی یک <b>فرم</b> است، و یک جلسهٔ ریپلی فرم نیست. یک جلسهٔ ریپلی دو حالت دارد و آن دو حالت به دو چیز متفاوت نیاز دارند.</p>
</header>

__SECTIONS__

<footer>این یک پیشنهاد است، نه یک تصمیم. هر تکه‌اش را می‌شود جدا برداشت یا رد کرد — اسلایدر سرعت به‌تنهایی هم می‌آید، بدون بقیهٔ تغییرات.</footer>
</div>
"""

STATES = ('<div class="states">'
  '<figure class="st"><figcaption>State 1 &mdash; flat</figcaption>'
  + panel("flat") +
  '<p>بی‌پوزیشن، شما در حال شکار هستید: زمان، قیمت، سرعت، و راهی برای مسلح‌کردن '
  'یک معامله با ریسکِ تعریف‌شده. ریسک اینجا یک کنترل است، نه یک گزارش.</p>'
  '</figure>'
  '<figure class="st"><figcaption>State 2 &mdash; in a position</figcaption>'
  + panel("pos") +
  '<p>با پوزیشن، شما در حال مدیریت هستید: استاپ کجاست، چند R جلو یا عقبید، و دو '
  'دکمه‌ای که کار را تمام می‌کنند. همان پنل، همان جا، محتوای دیگر.</p>'
  '</figure>'
  '<figure class="st"><figcaption>Collapsed</figcaption>'
  + panel("collapsed") +
  '<p>وقتی نمودار را می‌خواهید: فقط حرکت، سرعت و وضعیت. ۳۰۲ در ۱۸۷.</p>'
  '</figure></div>')

def build(path):
    secs = (
     SEC % (u"دو حالت، نه یک فرم", STATES)
     + SEC % (u"کنترل سرعت", (
        u'<p class="note" style="margin:0 0 22px">شما گفتید مثل آنِ Soft4FX '
        u'باشد — هم تیک و هم ثانیه، و مربعی نباشد، و از صفر همهٔ مقادیر را '
        u'داشته باشد. <b>من رابط Soft4FX را ندیده‌ام و وانمود نمی‌کنم دیده‌ام</b>؛ '
        u'این را از روی کاری که توصیف کردید ساخته‌ام. اگر آنجا چیز دیگری است، '
        u'بگویید تا اصلاح کنم.</p>'
        u'<p class="note" style="margin:0 0 26px">هشت خانهٔ مربعی رفت. جایش یک '
        u'شیار، یک پُرشدگی و یک دستگیره نشست — سه مستطیل، با هر عرضِ پیکسلی، '
        u'پس پیوسته دیده می‌شود و هر جایش را کلیک یا بکشید کار می‌کند. زیرش دو '
        u'عدد که دو سؤال متفاوت را جواب می‌دهند: <b>تیک بر ثانیه</b> یعنی کندل '
        u'چقدر زنده حس می‌شود، <b>ثانیه بر کندل</b> یعنی جلسه چقدر تند می‌رود. '
        u'دقتِ تیک که این دو را به هم وصل می‌کند، درست زیرشان است.</p>'
        u'<div class="spwrap">' + SPEEDS + u'</div>'))
     + SEC % (u"چه چیزهایی را برداشتم",
              tbl(REMOVED, u"بود", u"شد", u"چرا"))
     + SEC % (u"چه چیزهایی را اضافه کردم",
              tbl(ADDED, u"چه", u"چطور", u"چرا"))
     + SEC % (u"یک قانون که همه‌چیز را جمع کرد",
        u'<div class="rule"><b>نارنجی یعنی می‌شود لمسش کرد.</b> هر چیزی که فقط '
        u'اطلاعات است خاکستری می‌ماند — به همین دلیل خط پیشرفتِ زیر ساعت خاکستری '
        u'است و اسلایدر سرعت نارنجی. سبز و قرمز فقط جهت و سود/زیان را می‌گویند '
        u'و هیچ‌جای دیگر خرج نمی‌شوند.</div>'
        u'<p class="note">و یک چیز که <b>اندازه‌گیری شد نه فرض</b>: شکل‌های '
        u'دکمه‌های حرکت (‎◄ ► ▌▌ ■‎) از مجموعهٔ WGL4 هستند که Tahoma روی هر '
        u'ویندوزی دارد. اول Wingdings را امتحان کردم و در تست اصلاً رندر نشد، '
        u'پس کنار گذاشته شد.</p>'))
    open(path, "w", encoding="utf-8").write(
        HTML.replace("__CSS9__", CSS9).replace("__SECTIONS__", secs))

if __name__ == "__main__":
    build("/tmp/claude-0/faces/proposal.html")
    print("page built")
