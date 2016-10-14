package main;
use strict;
use warnings;

my %RBsmart_sets = (
	"Activate"		=> "Off",
	"AutoUp"		=> "Off",
	"AutoUpTime"	=> "09:00",
	"AutoDown"		=> "Off",
	"AutoDownTime" 	=> "20:00",
	"AutoDownDynamic" 	=> "None",
	"AutoUpDynamic" 	=> "None"
);

sub RBsmart_Initialize($) {
    my ($hash) = @_;

    $hash->{DefFn}      = 'RBsmart_Define';
    $hash->{UndefFn}    = 'RBsmart_Undef';
	$hash->{SetFn}    	= 'RBsmart_Set';
	$hash->{AttrFn}     = 'RBsmart_Attr';
	$hash->{NotifyFn} 	= 'RBsmart_Notify';

    $hash->{AttrList} =
           "RBsmartDevCmdUp "
          ."RBsmartDevCmdDown "
          ."RBsmartDevCmdStop "
          ."RBsmartDevUpTime "
          ."RBsmartDevDownTime "
          ."RBsmartInterruptDevState "
        . $readingFnAttributes;
}

sub RBsmart_Define($$) {
    my ($hash, $def) = @_;
    my @param = split('[ \t]+', $def);
        
    #$hash->{name}  = $param[0];
	
	if(int(@param) < 3) {
        return "too few parameters: define <name> Rbsmart <space seperated devices>";
    }
	splice(@param,0,2);
	my $re = join(" ",@param);
	$hash->{DEF}  = $re;
	RBsmart_CheckTwilightDevice($hash);
	RBsmart_CheckDevices($hash);
	RBsmart_CheckInterrupt($hash);

	RBsmart_CheckDynamicUpdate($hash);
	RBsmart_CheckAutoUpDown($hash);
    return undef;
}

sub RBsmart_InitInternals($) {
    my ($hash) = @_;
    RBsmart_CreateTimerAutoUpDown($hash,"Up");
	RBsmart_CreateTimerAutoUpDown($hash,"Down");
	RBsmart_DynamicUpdate($hash,"Up");
	RBsmart_DynamicUpdate($hash,"Down");
    return undef;
}

sub RBsmart_Undef($$) {
    my ($hash, $arg) = @_; 
    # nothing to do
	RemoveInternalTimer($hash);
    return undef;
}

sub RBsmart_DriveUp($){
	my ($hash) = @_;
	Log(3,"RBsmart: Automatisierter Eingriff -> DriveUp");
	readingsSingleUpdate( $hash, "DriveUp", "1", 1 );
	InternalTimer(gettimeofday()+1, "RBsmart_DriveUpDo", $hash, 0);
	RemoveInternalTimer($hash, "RBsmart_DriveStop");
	InternalTimer(gettimeofday()+$1, "RBsmart_DriveStop", $hash, 0) if (AttrVal($hash->{NAME},"RBsmartDevUpTime","") =~ /(\d+)/);
	RBsmart_CreateTimerAutoUpDown($hash,"Down");
}
sub RBsmart_DriveDownDo($){
	my ($hash) = @_;
	my @Dev = split(" ", $hash->{DEF});
	foreach (@Dev) {
		if (defined($defs{$_})){
			if(AttrVal($hash->{NAME},"RBsmartDevCmdDown","NONE") eq "NONE"){
				my $error = AnalyzeCommand(undef, "set $_ off");
			}else{
				fhem("set $_ ".AttrVal($hash->{NAME},"RBsmartDevCmdDown","default"));
				my $error = AnalyzeCommand(undef, "set $_ ".AttrVal($hash->{NAME},"RBsmartDevCmdDown","default"));
			}
		}
	}
	readingsSingleUpdate( $hash, "DriveDown", "0", 1 );
}

sub RBsmart_DriveUpDo($){
	my ($hash) = @_;
	my @Dev = split(" ", $hash->{DEF});
	foreach (@Dev) {
		if (defined($defs{$_})){
			if(AttrVal($hash->{NAME},"RBsmartDevCmdUp","default") eq "default"){
				my $error = AnalyzeCommand(undef, "set $_ on");
			}else{
				fhem("set $_ ".AttrVal($hash->{NAME},"RBsmartDevCmdUp","default"));
				my $error = AnalyzeCommand(undef, "set $_ ".AttrVal($hash->{NAME},"RBsmartDevCmdUp","default"));
			}
		}
	}
	readingsSingleUpdate( $hash, "DriveUp", "0", 1 );
}
sub RBsmart_DriveDown($){
	my ($hash) = @_;
	Log(3,"RBsmart: Automatisierter Eingriff -> DriveDown");
	my $downlock = 0;
	if(ReadingsVal($hash->{NAME},".USE_INTERRUPT_DEVICE",0)){
		if(my @Part = split(" ", AttrVal($hash->{NAME},"RBsmartInterruptDevState",""))){
			foreach my $Part (@Part) {
				my @Dev = split(/:/, $Part);
				if(scalar @Dev >1){
					my $matchdev = $Dev[0];
					splice(@Dev,0,1);
					my $re = join(":",@Dev);
					if (defined($defs{$matchdev})){
						if (Value($matchdev) =~ m/$re/){
							$downlock = 1;
							Log(3,"RBsmart: DriveDown -> ANGEHALTEN");
						}
					}
				}
			}
		}
	}
	if(!$downlock){
		InternalTimer(gettimeofday()+1, "RBsmart_DriveDownDo", $hash, 0);
		readingsSingleUpdate( $hash, "DriveDown", "1", 1 );
	}
	RemoveInternalTimer($hash, "RBsmart_DriveStop");
	InternalTimer(gettimeofday()+$1, "RBsmart_DriveStop", $hash, 0) if (AttrVal($hash->{NAME},"RBsmartDevDownTime","") =~ /(\d+)/);
	RBsmart_CreateTimerAutoUpDown($hash,"Down");
}

sub RBsmart_DriveStop($){
	my ($hash) = @_;
	Log(3,"RBsmart: Automatisierter Eingriff -> DriveStop");
	my @Dev = split(" ", $hash->{DEF});
	foreach (@Dev) {
		if (defined($defs{$_})){
			if(AttrVal($hash->{NAME},"RBsmartDevCmdStop","default") eq "default"){
				my $error = AnalyzeCommand(undef, "set $_ stop");
			}else{
				my $error = AnalyzeCommand(undef, "set $_ ".AttrVal($hash->{NAME},"RBsmartDevCmdStop","default"));
			}
		}
	}
}

sub RBsmart_CheckDynamicUpdate($){
	my ($hash) = @_;
	RemoveInternalTimer($hash, "RBsmart_CheckDynamicUpdate");
	my $dynamic = 0;
		for(my $i = 1; $i <= 2; $i++){
			my $direction = "";
			$direction = "Up" if ($i == 1);
			$direction = "Down" if ($i == 2);
			chomp(my $varhashkey1 = uc("Auto".$direction."DYN"));
			if(ReadingsVal($hash->{NAME},"Auto".$direction."Dynamic","None") =~ /(REAL|CIVIL|NAUTIC|ASTRONOMIC)/){
				my $dyntype = $1;
				my $read = "";
				if ($direction =~ /^Down$/){
					sunset_abs("$dyntype") =~ /^(\d+:\d+)/;
					$read = $1;
				}
				if ($direction =~ /^Up$/){
					sunrise_abs("$dyntype") =~ /^(\d+:\d+)/;
					$read = $1;
				}
				readingsSingleUpdate( $hash, "Auto".$direction."Time", $read, 0 );
				RBsmart_CreateTimerAutoUpDown($hash,$direction);
				Log(3,"RBsmart: Dynamisch Drive $direction -> Neuberechnung");
				$hash->{$varhashkey1} = "Ok: ".$dyntype;
				$dynamic = 1;
			}else{
				$hash->{$varhashkey1} = "Deactivated";
			}
		}
	if($dynamic){
		my ($SecNow, $MinNow, $HourNow, $DayNow, $MonthNow, $YearNow, $WDayNow, $YDNow, $SumTimeNow) = localtime(time);
		my $timersec = ((23-$HourNow)*3600)+((61-$MinNow)*60);
		InternalTimer(gettimeofday()+$timersec, "RBsmart_CheckDynamicUpdate", $hash, 0);
		RBsmart_CheckAutoUpDown($hash);
	}
}

sub RBsmart_CheckAutoUpDown($){
	my ($hash) = @_;
	for(my $i = 1; $i <= 2; $i++){
		my $direction = "";
		$direction = "Up" if ($i == 1);
		$direction = "Down" if ($i == 2);
		chomp(my $varhashkey1 = uc("Auto$direction"));
		if(ReadingsVal($hash->{NAME},".USE_DEVICE",0)){
			if(ReadingsVal($hash->{NAME},"Activate","Off") =~ /^On$/){
				if(ReadingsVal($hash->{NAME},"Auto$direction","Off") =~ /^On$/){
					if(ReadingsVal($hash->{NAME},"Auto".$direction."Time","NONE") =~ /^([0-9]|0[0-9]|1?[0-9]|2[0-3]):([0-5]?[0-9])$/){
						$hash->{READINGS}{uc(".USE_AUTO$direction")}{VAL} = 1;
						RBsmart_CreateTimerAutoUpDown($hash,"Up");
						RBsmart_CreateTimerAutoUpDown($hash,"Down");
					}else{
						$hash->{$varhashkey1} = "Not Running: Time not HH:MM";
						$hash->{READINGS}{uc(".USE_AUTO$direction")}{VAL} = 0;
					}
				}else{
					$hash->{$varhashkey1} = "Not Running: Auto$direction is Off";
					$hash->{READINGS}{uc(".USE_AUTO$direction")}{VAL} = 0;
				}
			}else{
				$hash->{$varhashkey1} = "Not Running: Global Activate is Off";
				$hash->{READINGS}{uc(".USE_AUTO$direction")}{VAL} = 0;
			}
		}else{
			$hash->{$varhashkey1} = "Not Running: Error in DEF";
			$hash->{$varhashkey1} = "Not Running: Error in DEF";
			$hash->{READINGS}{uc(".USE_AUTO$direction")}{VAL} = 0;
		}
	}			
					
}

sub RBsmart_CheckDevices($){
	my ($hash) = @_;
	if(my @Dev = split(" ", $hash->{DEF})){
		my $warningdev=0;
		foreach (@Dev) {
			if (!defined($defs{$_})){
				$warningdev = 1;
			}
			$hash->{STATE} = "Warning: Several Devices not exist" if ($warningdev);
			$hash->{STATE} = "Ok: Devices set" if (!$warningdev);
			$hash->{READINGS}{".USE_DEVICE"}{VAL} = 1;
		}
	}else{
		$hash->{STATE} = "Error: No Devices Set";
		readingsSingleUpdate( $hash, "Activate", "Off", 0 );
		$hash->{READINGS}{".USE_DEVICE"}{VAL} = 0;
	}
}

sub RBsmart_CreateTimerAutoUpDown($$){
	my ($hash, $direction) = @_;
	
	chomp(my $varhashkey1 = uc("Auto$direction"));
	RemoveInternalTimer($hash, "RBsmart_Drive$direction");

	if(ReadingsVal($hash->{NAME},uc(".USE_AUTO$direction"),0)){
		ReadingsVal($hash->{NAME},"Auto".$direction."Time","NONE") =~ /^([0-9]|0[0-9]|1?[0-9]|2[0-3]):([0-5]?[0-9])$/;
		my $Hour = 0;
		my $Min = 0;
		$Hour = $1;
		$Min = $2;
		my ($SecNow, $MinNow, $HourNow, $DayNow, $MonthNow, $YearNow, $WDayNow, $YDNow, $SumTimeNow) = localtime(time);
		$hash->{$varhashkey1} = "Ok ($Hour:$Min)";
		my $HourSec = 0;
		my $MinSec = 0;
		if(($Hour>$HourNow) || ($Hour==$HourNow && $Min>$MinNow)){
			$HourSec = $Hour*3600;
			$MinSec = $Min*60;
		}else{
			$HourSec = (23 + $Hour)*3600;
			$MinSec = (60 + $Min)*60;
		}
		my $HourNowSec = $HourNow*3600;
		my $MinNowSec = $MinNow*60;
		my $timersec = ($HourSec+$MinSec)-($HourNowSec+$MinNowSec+$SecNow);
		InternalTimer(gettimeofday()+$timersec, "RBsmart_Drive$direction", $hash, 0);
	}
}

sub RBsmart_CheckTwilightDevice($){
	my ($hash) = @_;
	RemoveInternalTimer($hash, "RBsmart_CheckTwilightDevice");
	my $twilightDev = (!$hash->{TWILIGHTDEVICE} || $hash->{TWILIGHTDEVICE});
	return 1 if (InternalVal($twilightDev,"TYPE","") =~ /^Twilight$/);
	if((my $analyzeString = AnalyzeCommand(undef, "jsonlist2 NAME=.*:FILTER=TYPE=Twilight NAME")) =~ /totalResultsReturned.*([1-9])/){
		$twilightDev = $analyzeString =~ /Internals.*NAME.*"(.*)"/;
		$hash->{TWILIGHTDEVICE}=$1;
		$hash->{READINGS}{uc(".USE_TWILIGHT")}{VAL} = 1;
		readingsSingleUpdate( $hash, "AutoSunAzimuth", ReadingsVal($1,"azimuth",0), 0 );
		readingsSingleUpdate( $hash, "AutoSunelevation", ReadingsVal($1,"elevation",0), 0 );
		InternalTimer(gettimeofday()+600, "RBsmart_CheckTwilightDevice", $hash, 0);
		return 1;
	}else{
		readingsSingleUpdate( $hash, "AutoSunAzimuth", 0, 0 );
		readingsSingleUpdate( $hash, "AutoSunelevation", 0, 0 );
		$hash->{TWILIGHTDEVICE}="Not Ok - No Device Found";
		$hash->{READINGS}{uc(".USE_TWILIGHT")}{VAL} = 0;
		return 0;
	}
	
}

sub RBsmart_Set($@) {
	my ($hash, @param) = @_;
	my $name = shift @param;
	my $opt = shift @param;
	my $value = join("", @param);
	
	if(!defined($RBsmart_sets{$opt})) {
		my $list =   "Activate:Off,On "
					."AutoUp:Off,On "
					."AutoUpTime "
					."AutoUpDynamic:None,REAL,CIVIL,NAUTIC,ASTRONOMIC "
					."AutoDown:Off,On "
					."AutoDownTime "
					."AutoDownDynamic:None,REAL,CIVIL,NAUTIC,ASTRONOMIC";
		return "Unknown argument $opt, choose one of $list";
	}
	if(($opt =~ /Activate|(Auto(Up|Down))$/) && !($value =~ /^On|Off$/)){
		return "Available Options <i>$opt</i>: (On/Off)"
	}elsif(($opt =~ /Activate|(Auto(Up|Down))$/) && ($value =~ /^On|Off$/)){
		readingsSingleUpdate( $hash, $opt, $value, 0 );
		RBsmart_CheckAutoUpDown($hash,);
	}
	if(($opt =~ /^Auto(Up|Down)Dynamic$/) && !($value =~ /^(None|REAL|CIVIL|NAUTIC|ASTRONOMIC)$/)){
		return "Available Options <i>$opt</i>: (None,REAL,CIVIL,NAUTIC,ASTRONOMIC)"
	}elsif(($opt =~ /^Auto(Up|Down)Dynamic$/) && ($value =~ /^(None|REAL|CIVIL|NAUTIC|ASTRONOMIC)$/)){
		readingsSingleUpdate( $hash, $opt, $value, 0 );
		InternalTimer(gettimeofday()+1, "RBsmart_CheckDynamicUpdate", $hash, 0);
	}
	if(($opt =~ /^Auto(Up|Down)Time$/) && !($value =~ /^([0-9]|0[0-9]|1?[0-9]|2[0-3]):[0-5]?[0-9]$/)){
		return "Please Set <i>$opt</i>: HH:MM"
	}elsif(($opt eq "AutoUpTime" || $opt eq "AutoDownTime") && ($value =~ /^([0-9]|0[0-9]|1?[0-9]|2[0-3]):[0-5]?[0-9]$/)){
		readingsSingleUpdate( $hash, $opt, $value, 0 );
		RBsmart_CheckDynamicUpdate($hash);
		RBsmart_CheckAutoUpDown($hash);
	}

	
	if(($opt =~ /^(Activate|(Auto(Up|Down)(Time|Dynamic)?))$/)){
		
		if(ReadingsVal($hash->{NAME},".USE_AUTOUP",0) && ReadingsVal($hash->{NAME},".USE_AUTODOWN",0)){
			if (RBsmart_CheckTimeBetween(ReadingsVal($hash->{NAME},"AutoDownTime","NONE"),ReadingsVal($hash->{NAME},"AutoUpTime","NONE"))){
				RemoveInternalTimer($hash, "RBsmart_DriveStop");
				RemoveInternalTimer($hash, "RBsmart_DriveDown");
				InternalTimer(gettimeofday()+5, "RBsmart_DriveDown", $hash, 0);
				
			}else{
				RemoveInternalTimer($hash, "RBsmart_DriveStop");
				RemoveInternalTimer($hash, "RBsmart_DriveUp");
				InternalTimer(gettimeofday()+5, "RBsmart_DriveUp", $hash, 0);
			}
		}
	}

	return undef;
}

sub RBsmart_Attr(@) {
	my ($cmd,$name,$attr_name) = @_;
	my $hash = $defs{$name};
	
	if($attr_name =~ /^RBsmartInterruptDevState$/){
		InternalTimer(gettimeofday()+1, "RBsmart_CheckInterrupt", $hash, 0);
		
	}
	return undef;
}
sub RBsmart_CheckInterrupt($){
	my ($hash) = @_;
	my $notifydef="";
	if(my @Part = split(" ", AttrVal($hash->{NAME},"RBsmartInterruptDevState",""))){
		foreach my $Part (@Part) {
			my @Dev = split(/:/, $Part);
			if(scalar @Dev >1){
				$notifydef .= "," if (length($notifydef)>2);
				$notifydef .= $Dev[0];
				splice(@Dev,0,1);
				my $re = join(":",@Dev);
				my $regex = eval { qr/$re/ };
				if ($@){
					$hash->{INTERDEVCMD} = "Error REGEX: $re"; 
					$hash->{READINGS}{".USE_INTERRUPT_DEVICE"}{VAL} = 0; 
					last;
				}else{
					$hash->{INTERDEVCMD} = "Ok";
					$hash->{READINGS}{".USE_INTERRUPT_DEVICE"}{VAL} = 1; 
					Log(3,"RBsmart: Interrupt wurde eingerichtet");
				}
			}else{
				$hash->{INTERDEVCMD} = "Error device1:state device2:state ...";
				$hash->{READINGS}{".USE_INTERRUPT_DEVICE"}{VAL} = 0; 
				last;				
			}
		}
	}else{
		$hash->{INTERDEVCMD} = "Notset";
		$hash->{READINGS}{".USE_INTERRUPT_DEVICE"}{VAL} = 0; 
	}
	$hash->{NOTIFYDEV} = $notifydef;
}

sub RBsmart_Notify($$){
	my ($ownhash, $devhash) = @_;
	
	my $ownname = $ownhash->{NAME};
	my $devname = $devhash->{NAME};
	return "" if(IsDisabled($ownname));
	my $devname = $devhash->{NAME};
	my $events = deviceEvents($devhash, 0);
	return if(!$events); # Some previous notify deleted the array.
	my $max = int(@{$events});
	
	if(ReadingsVal($ownname,".USE_INTERRUPT_DEVICE",0)){
		if(my @Part = split(" ", AttrVal($ownname,"RBsmartInterruptDevState",""))){
			foreach my $Part (@Part) {
				my @Dev = split(/:/, $Part);
				if(scalar @Dev >1){
					my $matchdev = $Dev[0];
					splice(@Dev,0,1);
					my $re = join(":",@Dev);
					my $regex = eval { qr/$re/ };
					if ($@){

					}else{
						for (my $i = 0; $i < $max; $i++) {
							my $s = $events->[$i];
							$s = "" if(!defined($s));
							if ($devname eq $matchdev){
								if ($s =~ m/$re/){
									RemoveInternalTimer($ownhash, "RBsmart_DriveStop");
									RemoveInternalTimer($ownhash, "RBsmart_DriveUp");
									InternalTimer(gettimeofday()+3, "RBsmart_DriveUp", $ownhash, 0);
								}else{
									if(ReadingsVal($ownname,".USE_AUTOUP",0) && ReadingsVal($ownname,".USE_AUTODOWN",0)){
										if (RBsmart_CheckTimeBetween(ReadingsVal($ownname,"AutoDownTime","NONE"),ReadingsVal($ownname,"AutoUpTime","NONE"))){
											RemoveInternalTimer($ownhash, "RBsmart_DriveStop");
											RemoveInternalTimer($ownhash, "RBsmart_DriveDown");
											InternalTimer(gettimeofday()+3, "RBsmart_DriveDown", $ownhash, 0);
										}
									}
								}
							}	
						}
					}
				}
			}
		}
	}	
}

sub RBsmart_CheckTimeBetween($$){
	my ($beginn, $end) = @_;
	my $beginnHour = 0;
	my $beginnMin = 0;
	my $endHour = 0;
	my $endMin = 0;
	
	if($beginn =~ /^([0-9]|0[0-9]|1?[0-9]|2[0-3]):([0-5]?[0-9])$/){
		$beginnHour = $1;
		$beginnMin = $2;
	}
	if($end =~ /^([0-9]|0[0-9]|1?[0-9]|2[0-3]):([0-5]?[0-9])$/){
		$endHour = $1;
		$endMin = $2;
	}
	
	my ($SecNow, $MinNow, $HourNow, $DayNow, $MonthNow, $YearNow, $WDayNow, $YDNow, $SumTimeNow) = localtime(time);
	#Beginn vor Ende
	return 1 if($HourNow > $beginnHour && $HourNow < $endHour);
	return 1 if($HourNow == $beginnHour && $HourNow < $endHour && $MinNow >= $beginnMin);
	return 1 if($HourNow > $beginnHour && $HourNow == $endHour && $MinNow < $beginnMin);
	
	#Ende vor Beginn
	return 1 if(($HourNow > $beginnHour || $HourNow < $endHour) && $beginnHour > $endHour);
	return 1 if($HourNow == $beginnHour && $MinNow >= $beginnMin && $beginnHour > $endHour);
	return 1 if($HourNow == $endHour && $MinNow < $endMin && $beginnHour > $endHour);
	
	return 0;
}
1;

=pod
=begin html

<a name="RBsmart"></a>
<h3>RBsmart</h3>
<ul>
    Mit <i>RBsmart</i> steht ein Hilfsmodul bereit mit dem es möglich ist auf einfachem Wege 
	eine Smarte Rolladensteuerung zu implementieren. Es sind keine manuellen Definitionen von
	Notifys oder Ats anzulegen.
    <br><br>
    <a name="RBsmartdefine"></a>
    <b>Define</b>
    <ul>
        <code>define <name> RBsmart <space seperated devices></code>
        <br>
        Example: <code>define RBsmart.Kinderzimmer RBsmart Device1 Device2</code>
        <br>
    </ul>
    <br>
    
    <a name="RBsmartset"></a>
    <b>Set</b><br>
	<ul>
		  <li><i>Activate</i> (Off/On)<br>
			  Aktiviert den Automatisierungsprozess des Devices. Hier wird für den 
			  ganzen Baustein entschieden ob Automatisierungen ein- oder ausgeschaltet sind</li>
		  <li><i>Auto(Up|Down)</i> (Off/On)<br>
			  Akiviert das Automatische Hoch-/Runterfahren mit der angegebenen Zeit</li>
		  <li><i>Auto(Up|Down)Time</i> HH:MM<br>
			  Uhrzeit zum Hoch-/Runterfahren (Default: UP->09:00 DOWN->20:00)</li>
		  <li><i>Auto(Up|Down)Dynamic</i> (None|REAL|CIVIL|NAUTIC|ASTRONOMIC)<br>
			  Bestimmt das dynamische hoch und runterfahren. Verschiedene Modi wählbar.</li>
	</ul>
    <br>

    <br>
    
    <a name="RBsmartattr"></a>
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

=end html

=cut
