//+------------------------------------------------------------------+
//|                                              SSR_ReportStyle.mqh |
//|                 SS Replay - One Skin For Every Report (L4)       |
//|                                                                  |
//|  The session statement and the class report are two documents     |
//|  that must look like one product. They were going to be two       |
//|  copies of the same four hundred lines of CSS, and the first      |
//|  colour changed in one of them would have made them two products. |
//|                                                                  |
//|  So the skin lives here and both include it. Nothing in this file |
//|  knows what a trade is.                                           |
//+------------------------------------------------------------------+
#ifndef SSR_REPORT_STYLE_MQH
#define SSR_REPORT_STYLE_MQH


//+------------------------------------------------------------------+
void SSRWriteReportHead(const int h, const string title)
  {
   FileWriteString(h,
      "<!doctype html><html><head><meta charset=\"utf-8\">\r\n"
      "<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">\r\n"
      "<title>" + title + "</title><style>\r\n"
      ":root{color-scheme:light;\r\n"
      " --page:#f0f3f5; --panel:#ffffff; --line:#dde2e7; --line2:#eef1f4;\r\n"
      " --head:#eef1f4; --text:#16181b; --muted:#5c636b; --grid:#e0e6ec;\r\n"
      " --gain:#0e9f58; --loss:#a93226; --amber:#a35a00;\r\n"
      " --equity:#1f6fb2; --equityfill:rgba(31,111,178,.14);\r\n"
      " --ambbg:#fff6e5; --ambline:#e3c88a; --ambtext:#5a3d00}\r\n"
      "@media (prefers-color-scheme:dark){:root:not([data-theme=\"light\"]){\r\n"
      " color-scheme:dark;\r\n"
      " --page:#0f141a; --panel:#161c23; --line:#26333f; --line2:#1e2831;\r\n"
      " --head:#1b242e; --text:#dce4ec; --muted:#8296aa; --grid:#242f3a;\r\n"
      " --gain:#3ecf77; --loss:#e5484d; --amber:#e0a33a;\r\n"
      " --equity:#4e9fe6; --equityfill:rgba(78,159,230,.17);\r\n"
      " --ambbg:#241d0d; --ambline:#5a4718; --ambtext:#e8d5a8}}\r\n"
      ":root[data-theme=\"dark\"]{color-scheme:dark;\r\n"
      " --page:#0f141a; --panel:#161c23; --line:#26333f; --line2:#1e2831;\r\n"
      " --head:#1b242e; --text:#dce4ec; --muted:#8296aa; --grid:#242f3a;\r\n"
      " --gain:#3ecf77; --loss:#e5484d; --amber:#e0a33a;\r\n"
      " --equity:#4e9fe6; --equityfill:rgba(78,159,230,.17);\r\n"
      " --ambbg:#241d0d; --ambline:#5a4718; --ambtext:#e8d5a8}\r\n");

   FileWriteString(h,
      "*{box-sizing:border-box}\r\n"
      "body{font-family:Tahoma,Segoe UI,sans-serif;font-size:13px;color:var(--text);"
      "background:var(--page);margin:0;padding:28px}\r\n"
      ".w{max-width:1000px;margin:0 auto}\r\n"
      ".top{display:flex;align-items:flex-start;justify-content:space-between;gap:16px}\r\n"
      "h1{font-size:21px;margin:0 0 4px}\r\n"
      "h2{font-size:13px;margin:30px 0 9px;color:var(--muted);text-transform:uppercase;"
      "letter-spacing:.06em}\r\n"
      ".sub{color:var(--muted);margin:0 0 20px;font-size:12px}\r\n"
      ".thm{font:inherit;font-size:11px;color:var(--muted);background:var(--panel);"
      "border:1px solid var(--line);border-radius:4px;padding:5px 11px;cursor:pointer;"
      "white-space:nowrap}\r\n"
      ".thm:hover{color:var(--text)}\r\n"
      ".caveat{background:var(--ambbg);border:1px solid var(--ambline);"
      "border-left:4px solid var(--amber);padding:11px 14px;margin:0 0 20px;"
      "color:var(--ambtext)}\r\n"
      ".kpi{display:flex;flex-wrap:wrap;gap:10px;margin:0 0 4px}\r\n"
      ".kpi div{background:var(--panel);border:1px solid var(--line);"
      "padding:10px 14px;min-width:132px}\r\n"
      ".kpi b{display:block;font-size:18px;margin-top:3px}\r\n"
      ".kpi span{font-size:11px;color:var(--muted);text-transform:uppercase;"
      "letter-spacing:.04em}\r\n");

   FileWriteString(h,
      "table{width:100%;border-collapse:collapse;background:var(--panel);"
      "border:1px solid var(--line);font-size:12px}\r\n"
      "th{text-align:left;background:var(--head);padding:8px 9px;"
      "border-bottom:1px solid var(--line);font-size:11px;text-transform:uppercase;"
      "letter-spacing:.04em;color:var(--muted);font-weight:600}\r\n"
      "td{padding:7px 9px;border-bottom:1px solid var(--line2)}\r\n"
      "td.n,th.n{text-align:right;font-variant-numeric:tabular-nums}\r\n"
      "td.dim{color:var(--muted)}\r\n"
      "tr.head td{background:var(--head);color:var(--muted);font-size:11px;"
      "text-transform:uppercase;letter-spacing:.04em}\r\n"
      ".g{color:var(--gain);font-weight:700} .r{color:var(--loss);font-weight:700}\r\n"
      ".amb{color:var(--amber)}\r\n"
      ".scroll{overflow-x:auto}\r\n"
      "details{margin:8px 0 0}\r\n"
      "summary{cursor:pointer;color:var(--muted);font-size:11px;"
      "text-transform:uppercase;letter-spacing:.04em;padding:4px 0}\r\n");

   FileWriteString(h,
      ".fig{position:relative;background:var(--panel);border:1px solid var(--line);"
      "padding:10px 12px 8px}\r\n"
      ".fig svg{display:block;width:100%;height:auto}\r\n"
      ".figcap{color:var(--muted);font-size:11px;margin:6px 2px 0;line-height:1.6}\r\n"
      ".tip{position:absolute;top:8px;pointer-events:none;opacity:0;"
      "background:var(--panel);border:1px solid var(--line);padding:5px 9px;"
      "font-size:11px;white-space:nowrap;box-shadow:0 1px 6px rgba(0,0,0,.16);"
      "font-variant-numeric:tabular-nums;transition:opacity .08s}\r\n"
      ".hrs{display:flex;gap:2px;height:120px;position:relative;margin:2px 0 0}\r\n"
      ".hr{flex:1;position:relative}\r\n"
      ".hmid{position:absolute;left:0;right:0;top:50%;height:1px;"
      "background:var(--muted);opacity:.35}\r\n"
      ".hb{position:absolute;left:0;right:0;border-radius:3px}\r\n"
      ".hb.g{bottom:50%;background:var(--gain)}\r\n"
      ".hb.r{top:50%;background:var(--loss)}\r\n"
      ".hax{display:flex;gap:2px;margin:4px 0 0;color:var(--muted);font-size:10px;"
      "font-variant-numeric:tabular-nums}\r\n"
      ".hax div{flex:1;text-align:center}\r\n"
      ".bar{position:relative;width:34%;min-width:150px}\r\n"
      ".bz{position:absolute;left:50%;top:2px;bottom:2px;width:1px;"
      "background:var(--muted);opacity:.35}\r\n"
      ".bf{position:absolute;top:5px;bottom:5px;border-radius:3px}\r\n"
      ".bf.g{background:var(--gain)} .bf.r{background:var(--loss)}\r\n"
      //--- the flex box is a DIV inside the cell, never the cell
      //--- itself: display:flex on a <td> takes it out of the table
      //--- box model and the column stops lining up with its header
      "td.shot{padding:5px 9px}\r\n"
      "td.shot div{display:flex;gap:4px}\r\n"
      "td.shot img{display:block;width:78px;height:auto;"
      "border:1px solid var(--line);border-radius:2px}\r\n"
      "td.shot a:focus-visible img{outline:2px solid var(--equity);"
      "outline-offset:1px}\r\n"
      //--- the class report's own row strip. It lives in the shared skin
      //--- rather than in a second <style> inside the body: one place
      //--- where a colour is defined is the entire point of this file.
      ".srow{display:flex;align-items:center;gap:10px;margin:0 0 3px}\r\n"
      ".sname{width:148px;flex:none;font-size:12px;text-align:right;"
      "overflow:hidden;text-overflow:ellipsis;white-space:nowrap}\r\n"
      ".strip{position:relative;flex:1;height:20px;background:var(--line2);"
      "border:1px solid var(--line);border-radius:3px}\r\n"
      ".strip.off{opacity:.4}\r\n"
      ".smark{position:absolute;top:3px;width:6px;height:12px;"
      "border-radius:2px;margin-left:-3px}\r\n"
      ".smark.g{background:var(--gain)} .smark.r{background:var(--loss)}\r\n"
      ".saxis{display:flex;justify-content:space-between;color:var(--muted);"
      "font-size:11px;margin:6px 0 0 158px}\r\n"
      "@media print{body{background:#fff}.thm{display:none}}\r\n"
      "</style></head><body><div class=\"w\">\r\n");
  }

void SSRWriteThemeToggle(const int h)
  {
   FileWriteString(h,
      "<script>\r\n"
      "(function(){var r=document.documentElement,b=document.getElementById('thm');\r\n"
      "if(!b)return;\r\n"
      "function set(t){if(t){r.setAttribute('data-theme',t);}"
      "else{r.removeAttribute('data-theme');}\r\n"
      " b.textContent=(t===null?(sd?'Light':'Dark')"
      ":(t===(sd?'light':'dark')?(sd?'Dark':'Light'):'System'));\r\n"
      " try{if(t){localStorage.setItem('ssr-thm',t);}"
      "else{localStorage.removeItem('ssr-thm');}}catch(e){}}\r\n"
      "var sd=(window.matchMedia&&"
      "matchMedia('(prefers-color-scheme:dark)').matches);\r\n"
      "var cur=null;try{cur=localStorage.getItem('ssr-thm');}catch(e){}\r\n"
      "if(cur!=='dark'&&cur!=='light'){cur=null;}\r\n"
      "set(cur);\r\n"
      "b.onclick=function(){cur=(cur===null?(sd?'light':'dark')"
      ":(cur===(sd?'light':'dark')?(sd?'dark':'light'):null));set(cur);};})();\r\n"
      "</script>\r\n");
  }

#endif // SSR_REPORT_STYLE_MQH
//+------------------------------------------------------------------+
