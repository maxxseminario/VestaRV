# TSMC 65 nm CMN65GP kit setup

# License files
export LM_LICENSE_FILE=5280@poseidon:27020@poseidon:1717@poseidon
export CDS_LIC_FILE=5280@poseidon
export CDS_LIC_ONLY

# Environment Variables
export CADENCE_HOME=/opt/cadence
export KIT_HOME=/opt/design_kits

export VIRTUOSO_HOME=$CADENCE_HOME/IC618
export cdsPath=$VIRTUOSO_HOME/tools/bin:$VIRTUOSO_HOME/tools/dfII/bin
export CDS_AUTO_64BIT=ALL
export CDS_LOAD_ENV=CWDElseHome
export CDS_Netlisting_Mode=Analog
export OA_UNSUPPORTED_PLAT=linux_rhel60 # makes QRC work on OpenSuse, pretending as if it were RHEL 6.0

# export PVS_HOME=$CADENCE_HOME/PVS201
export PVS_HOME=/opt/cadence/PEGASUS221
export pvsPath=$PVS_HOME/tools/bin

export QRC_HOME=$CADENCE_HOME/EXT191
export qrcPath=$QRC_HOME/bin
export QRC_ENABLE_EXTRACTION=t

# export ASSURAHOME=/opt/cadence/ASSURA415
# export assuraPath=$ASSURAHOME/bin

export SPECTRE_HOME=$CADENCE_HOME/SPECTRE201
export spectrePath=$SPECTRE_HOME/bin
export SPECTRE_DEFAULTS="-E +multithread"

export XCELIUM_HOME=$CADENCE_HOME/XCELIUM2009
export xceliumPath=$XCELIUM_HOME/tools/bin

export INNOVUS_HOME=$CADENCE_HOME/INNOVUS201
export innovusPath=$INNOVUS_HOME/tools/bin

export GENUS_HOME=$CADENCE_HOME/GENUS191
export genusPath=$GENUS_HOME/bin

export MENTOR_HOME=/opt/mentor
export CALIBRE_HOME=$MENTOR_HOME/calibre/aoj_cal
export calibrePath=$CALIBRE_HOME/bin
export mentorPath=$MENTOR_HOME/bin
export MGC_CALIBRE_REALTIME_VIRTUOSO_ENABLED=1
export MGC_TMPDIR=/tmp
export OA_PLUGIN_PATH=${CALIBRE_HOME}/shared/pkgs/icv/tools/queryskl
export LD_LIBRARY_PATH=${CALIBRE_HOME}/shared/pkgs/icv/tools/calibre_client/lib/64:${LD_LIBRARY_PATH}

export linuxPath=~/.local/bin:/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin

export PATH=$cdsPath:$assuraPath:$qrcPath:$pvsPath:$spectrePath:$genusPath:$innovusPath:$xceliumPath:$mentorPath:$calibrePath:$linuxPath:$PATH




# Suppress warnings about using CentOS instead of Redhat in IC617, CCR 1739524.
export W3264_NOWARN_UNSUPPORTED_CENTOS=1
export W3264_NO_HOST_CHECK=1

# Specify the explicit folder where the .simrc file is located. This ENV
# variable overrides all others.  This is done since IC617 seemed to be
# ignoring it if placed in the CWD.  This file specifies global nets needed for
# CDL netlisting to work during LVS.
export SIMRC=ic

# Set up multi-host simulation
export LBS_CLUSTER_MASTER=poseidon

# Debug ICRP ADE XL sweeps for during CentoS 7 migration
#export AXL_PEJM_DEBUG=3
