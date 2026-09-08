SS Replay
=========

Everything in this package is already compiled. No MetaEditor, no F7.

INSTALL  (three steps, once)
  1. MetaTrader:  File  ->  Open Data Folder
  2. Drag the MQL5 folder from THIS package onto the MQL5 folder there.
     Choose "Replace the files in the destination".
  3. MetaTrader -> Navigator (left panel) -> right-click -> Refresh

IF SOMETHING FROM AN EARLIER RUN IS IN THE WAY
  Navigator -> Scripts -> SSReplay -> Spike -> SSR_Z_Cleanup
  Drag it onto a chart. It closes every leftover replay chart and deletes
  every leftover .SSR symbol. Safe to run at any time.

RUN THE SELF TEST
  Navigator -> Scripts -> SSReplay -> QA -> SSR_QA_Smoke -> drag onto a chart
  Press Ctrl+T first, so the chart is tall enough to measure the panel.

  It writes every line, as it happens, to:
      MQL5\Files\SSReplay\qa-result.txt
  Even if it stops half way, that file holds everything up to the point it
  stopped and its last line names the place. Send that one file.

IF A SCRIPT WILL NOT GO AWAY
  A script stays on the chart while it is still running.
  Right-click on the chart -> Remove Script, or close that chart.

RUN THE TOOL
  Navigator -> Expert Advisors -> SSReplay -> SSReplayStandalone
  Drag onto a chart. Press H for the list of keys.

KEYS
  Space      play / pause
  Left/Right one candle back / forward
  PgUp/PgDn  ten candles back / forward
  R          stop and target lines on the chart
  Tab        take the trade the lines describe
  X          flip them: long <-> short
  H          the full list
  0          start the session over (asks first)

  Every trade is virtual. Nothing ever reaches a broker.
