# RBsmart
 Mit <i>RBsmart</i> steht ein Hilfsmodul bereit mit dem es möglich ist auf einfachem Wege 
eine Smarte Rolladensteuerung zu implementieren. Es sind keine manuellen Definitionen von
Notifys oder Ats anzulegen.
<br><br>
<a name="RBsmartdefine"></a>
<b>Define</b>
<code>define name RBsmart space seperated devices</code>
<br>
Example: <code>define RBsmart.Kinderzimmer RBsmart Device1 Device2</code>
<br>
<br>   
<b>Set</b><br>
<ul>
<li><i>Activate</i> (Off/On)<br>
Aktiviert den Automatisierungsprozess des Devices. Hier wird für den 
ganzen Baustein entschieden ob Automatisierungen ein- oder ausgeschaltet sind</li>
<li><i>Auto(Up|Down)</i> (Off/On)<br>
Akiviert das Automatische Hoch-/Runterfahren mit der angegebenen Zeit</li>
<li><i>Auto(Up|Down)Time</i> HH:MM<br>
Uhrzeit zum Hoch-/Runterfahren (Default: UP->09:00 DOWN->20:00)</li>
<li><i>Auto(Up|Down)Dynamic</i> (None|REAL|civil|naut|astro)<br>
<li><i>Auto(Up|Down)Dynamic</i> (None|REAL|CIVIL|NAUTIC|ASTRONOMIC)<br>
Bestimmt das dynamische hoch und runterfahren. Verschiedene Modi wählbar.</li>
</ul>
<br>

<br>

<b>Attributes</b>
<ul>
<li><i>RBsmartDeviceCmd(Up|Down|Stop)</i> <br>
Ein Benutzerdefinierter Befehl um die Rolladen Hoch-/Runterfahren oder zu
Stoppen (default: UP->on DOWN->off STOP->stop)
</li>
<li><i>RBsmartDeviceCmd(Up|Down)Time</i> <br>
Wenn die Devices keinen Internen Timer besitzen kann mit dem Parameter bestimmt
werden wie lange die Rolladen Hoch oder Runterfahren bevor diese den Stop Befehl
bekommen
</li>
<li><i>RBsmartInterruptDevState</i> <br>
Hier werden Leerzeichengetrennt Devices mit dem State angegeben der dafür sorgt das die Rolladen
nicht heruntergefahren werden oder hoch gefahren werden sollte dieser Status eintreten.<br>
Bsp: <code>attr RBsmart.Kinderzimmer Fenstersensor:closed Tuersensor:(closed|tipped)</code>
</li>
</ul>
</ul>
