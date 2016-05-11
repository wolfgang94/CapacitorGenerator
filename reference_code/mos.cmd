!ICWin wrapper for the mos perl script

!------------------------------------------------------------------------------
! Get tech info
!------------------------------------------------------------------------------

IF (FILE_EXISTS("TECH.CMD") == 1) @TECH.CMD ;
IF (MACRO_EXISTS(#TECH) == 0) {
    ERROR "Technology not set." ;
}

!------------------------------------------------------------------------------
! Prompt for device parameters
!------------------------------------------------------------------------------

LOCAL #valid = 0 ;

DEFAULT LOCAL #type = "" ;
WHILE ({CMP(%type, "n")} && {CMP(%type, "p")}) {
    LOCAL #type $PROMPT="Device type (n/p, required): " ;
}

DEFAULT LOCAL #hv $PROMPT="Device is HV (y/N): " ;
IF ({CMP(%hv, "y")}) {
    #hv = "n" ;
}

DEFAULT LOCAL #width = "" ;
WHILE ({CMP(%width, "")} == 0 || {VALID_REAL("%width")} == 0) {
    LOCAL #width $PROMPT="Device width (required): " ;
}

#valid = 0 ;
DEFAULT LOCAL #length = "" ;
WHILE (%valid == 0 && {VALID_REAL("%length")} == 0) {
    LOCAL #length $PROMPT="Device length (enter for default): " ;
    IF ({CMP(%length, "")} == 0) {
        #valid = 1 ;
    }
}

DEFAULT LOCAL #name = "" ;
DEFAULT LOCAL #post = "" ;
DEFAULT LOCAL #ntc = "" ;
DEFAULT LOCAL #nbc = "" ;
DEFAULT LOCAL #nsc = "" ;
DEFAULT LOCAL #ndc = "" ;

DEFAULT LOCAL #extra $PROMPT="Set extra options (y/N): " ;
IF ({CMP(%extra, "y")} == 0) {

    #valid = 0 ;
    WHILE (%valid == 0 && {VALID_CELL_NAME("%name")} == 0) {
        LOCAL #name $PROMPT="Device name (enter for default): " ;
        IF ({CMP(%name, "")} == 0) {
            #valid = 1 ;
        }
    }

    LOCAL #post $PROMPT="Device name postfix (enter for none): " ;
    if ({CMP(%post, "")}) {
        #name = "%name^_%post" ;
   }

    #valid = 0 ;
    WHILE (%valid == 0 && {VALID_INT("%ntc")} == 0) {
        LOCAL #ntc $PROMPT="Number of top gate contact rows (default 1): " ;
        IF ({CMP(%ntc, "")} == 0) {
            #valid = 1 ;
        }
    }

    #valid = 0 ;
    WHILE (%valid == 0 && {VALID_INT("%nbc")} == 0) {
        LOCAL #nbc $PROMPT="Number of bottom gate contact rows (default 1): " ;
        IF ({CMP(%nbc, "")} == 0) {
            #valid = 1 ;
        }
    }

    #valid = 0 ;
    WHILE (%valid == 0 && {VALID_INT("%nsc")} == 0) {
        LOCAL #nsc $PROMPT="Number of source gate contact columns (default 1): " ;
        IF ({CMP(%nsc, "")} == 0) {
            #valid = 1 ;
        }
    }

    #valid = 0 ;
    WHILE (%valid == 0 && {VALID_INT("%ndc")} == 0) {
        LOCAL #ndc $PROMPT="Number of drain gate contact columns (default 1): " ;
        IF ({CMP(%ndc, "")} == 0) {
            #valid = 1 ;
        }
    }
}

LOCAL #device = "%type" ;
IF (CMP(%hv, "y") == 0) {
    #device = "%device^hv" ;
}
#device = "%device^:%width^:%length^:%name" ;
#device = "%device^:%ntc^:%nbc^:%nsc^:%ndc" ;

DOS "perl -x%EXEC.DIR %EXEC.DIR^mos.pl %TECH^.json %device & pause" ;
@MOS_OUT.CMD ;

