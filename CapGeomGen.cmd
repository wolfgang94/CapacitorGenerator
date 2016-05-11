!generates capacitors for given capacitance and physical constraint (Length or Width)

XSELECT OFF;

!------------------------------------------------------------------------------
! Get tech info
!Note from Barry's mos wrapper
!------------------------------------------------------------------------------

IF (FILE_EXISTS("TECH.CMD") == 1) @TECH.CMD ;
IF (MACRO_EXISTS(#TECH) == 0) {
    ERROR "Technology not set." ;
}

!------------------------------------------------------------------------------
! Prompt for device parameters
!------------------------------------------------------------------------------

DEFAULT LOCAL #DESIREDCAP = "" ;
DEFAULT LOCAL #CONSTRAINTPARAM = "" ;
DEFAULT LOCAL #MAXMETAL = "";
DEFAULT LOCAL #TOPLAYER = "";
DEFAULT LOCAL #BOTTOMLAYER = "";

IF (#TOPMETAL == "M7") {  
    LOCAL #MAXMETAL=7;
}
ELSEIF (TOPMETAL == "M6") {
        LOCAL #MAXMETAL=6;
}
ELSEIF (TOPMETAL == "M5") {
        LOCAL #MAXMETAL=5;
}
ELSEIF (TOPMETAL == "M4") {
        LOCAL #MAXMETAL=4;
}
ELSE {
ERROR "Topmetal not set.";
}


#valid = 0 ;
WHILE (%valid == 0 && {VALID_REAL("%DESIREDCAP")} == 0) {
    LOCAL #DESIREDCAP $PROMPT = "Enter the desired capacitance (in UNITS):";
    IF ({CMP(%DESIREDCAP, "")} == 0) {
        #valid = 1 ;
    }
}

DEFAULT LOCAL #CONSTRAINTPARAM = "" ;
WHILE ({CMP(%type, "w")} && {CMP(%type, "l")}) {
    LOCAL #type $PROMPT="Constraining parameter (selection of w or l required): " ;
}

#valid = 0 ;
WHILE ((%valid == 0) && (VALID_REAL(%CONSTRAINTPARAMVALUE) == 0)) {
	LOCAL #CONSTRAINTPARAMVALUE $PROMPT = "What is the desired value of %CONSTRAINTPARAM ?: ";
    IF ({CMP(%CONSTRAINTPARAMVALUE, "")} == 0) {
        #valid = 1 ;
    }
} 

!-----------------------------------------------------------------------------
! input for capacitor layers used, unsure about how to specify
! this, mayb there should be a default?
! also specified with #-# or two seperate prompts? 2nd one saves me some
! work with regex.
!-----------------------------------------------------------------------------


DEFAULT LOCAL #extra $PROMPT="Set used layers (y/N)?: " ;
IF ({CMP(%extra, "y")} == 0) {    

   #valid = 0 ;
   WHILE (%valid == 0 && (({VALID_INT("%BOTTOMLAYER")} == 0) || ({CMP(%BOTTOMLAYER, "g")}))) {
	   LOCAL #BOTTOMLAYER $PROMPT = "Lowest layer to be used? ";
       IF (({CMP(%BOTTOMLAYER, "")} == 0) || ((%BOTTOMLAYER > 7) && (%BOTTOMLAYER < 0)) || ({CMP(%BOTTOMLAYER, "G")} ==1))  {
	   #valid = 1 ;
       }
   } 

   #valid = 0 ;
   WHILE (%valid == 0 && {VALID_INT("%TOPLAYER")} == 0) {
	   LOCAL #TOPLAYER $PROMPT = "uppermost metal use? (must be less than or equal to %MAXMETAL)";
       IF (({CMP(%TOPLAYER, "")} == 1) || ((%TOPLAYER >= %MAXMETAL) || ($BOTTOMLAYER > $TOPLAYER)) {
	   #valid = 1 ;
       }
   } 
}

LOCAL #layers = "";
IF (CMP(%extra, "y") ==0) {
   #layers =  "%BOTTOMLAYER-%TOPLAYER";
}
ELSE {
     #layers = "0-7";
}

DOS "perl -x%EXEC.DIR %EXEC.DIR^CapGeomGen.pl %TECH %DESIREDCAP %CONSTRAINTPARAM %CONSTRAINTPARAMVALUE & PAUSE";
