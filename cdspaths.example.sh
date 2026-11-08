# VestaRV: Cadence and Mentor tool environment for the TSMC 65 nm CMN65GP kit.
# TEMPLATE. Copy to cdspaths.sh (untracked, gitignored) and edit for your site:
#   cp cdspaths.example.sh cdspaths.sh
# Scripts source it through tools/source_cdspaths.sh, which also honours
# $CDSPATHS and, in a git worktree, the main checkout's cdspaths.sh.
# Source before any Virtuoso, Genus, Innovus, Xcelium, Pegasus or Calibre run.
# PATH order below is load bearing: the kit tools come before the system ones.
# Every value marked SITE is a placeholder; the install directory names below
# are the tool versions the flows were validated with.

# SITE: licence servers (port@host, colon separated).
export LM_LICENSE_FILE=${LM_LICENSE_FILE:-5280@license-server.example:27020@license-server.example:1717@license-server.example}
export CDS_LIC_FILE=${CDS_LIC_FILE:-5280@license-server.example}
export CDS_LIC_ONLY

# SITE: install roots.
export CADENCE_HOME=${CADENCE_HOME:-/path/to/cadence}
export KIT_HOME=${KIT_HOME:-/path/to/design_kits}

export VIRTUOSO_HOME=$CADENCE_HOME/IC618
export cdsPath=$VIRTUOSO_HOME/tools/bin:$VIRTUOSO_HOME/tools/dfII/bin
export CDS_AUTO_64BIT=ALL
export CDS_LOAD_ENV=CWDElseHome
export CDS_Netlisting_Mode=Analog
export OA_UNSUPPORTED_PLAT=linux_rhel60 # QRC runs on OpenSUSE only if it is told it is RHEL 6.0

# export PVS_HOME=$CADENCE_HOME/PVS201
export PVS_HOME=$CADENCE_HOME/PEGASUS221
export pvsPath=$PVS_HOME/tools/bin

export QRC_HOME=$CADENCE_HOME/EXT191
export qrcPath=$QRC_HOME/bin
export QRC_ENABLE_EXTRACTION=t

# export ASSURAHOME=$CADENCE_HOME/ASSURA415
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

# SITE: Mentor install root.
export MENTOR_HOME=${MENTOR_HOME:-/path/to/mentor}
export CALIBRE_HOME=$MENTOR_HOME/calibre/aoj_cal
export calibrePath=$CALIBRE_HOME/bin
export mentorPath=$MENTOR_HOME/bin
export MGC_CALIBRE_REALTIME_VIRTUOSO_ENABLED=1
export MGC_TMPDIR=/tmp
export OA_PLUGIN_PATH=${CALIBRE_HOME}/shared/pkgs/icv/tools/queryskl
export LD_LIBRARY_PATH=${CALIBRE_HOME}/shared/pkgs/icv/tools/calibre_client/lib/64:${LD_LIBRARY_PATH}

export linuxPath=~/.local/bin:/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin

export PATH=$cdsPath:$assuraPath:$qrcPath:$pvsPath:$spectrePath:$genusPath:$innovusPath:$xceliumPath:$mentorPath:$calibrePath:$linuxPath:$PATH




# IC617 warns about CentOS where it expects Red Hat (Cadence CCR 1739524).
export W3264_NOWARN_UNSUPPORTED_CENTOS=1
export W3264_NO_HOST_CHECK=1

# SIMRC names the directory holding .simrc and overrides every other search
# path; IC617 ignores the file in the CWD. That .simrc declares the global nets
# CDL netlisting needs for LVS.
export SIMRC=ic

# Multi-host simulation. SITE: the LBS cluster master host.
export LBS_CLUSTER_MASTER=${LBS_CLUSTER_MASTER:-lbs-master.example}

# ADE XL sweep debug.
#export AXL_PEJM_DEBUG=3
