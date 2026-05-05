# Prints every combination of corner model data to standard output.  Redirect to .pcf file.
# Targets TSMC 0.13 um low-power technology CM013LP

import sys

print """
libId = ddGetObj("tsmcN65")
libPath = ddGetObjReadPath( libId )
pcfPath = strcat(libPath "/../models/spectre")
corAddProcess( "tsmcN65" pcfPath  "multipleModelLib" )

corAddModelFileAndSectionChoices( "tsmcN65" "cor_rfmos.scs" '("ff_rfmos" "fs_rfmos" "sf_rfmos" "ss_rfmos" "tt_rfmos" ) )
corAddModelFileAndSectionChoices( "tsmcN65" "cor_rfmos_18.scs" '("ff_rfmos_18" "fs_rfmos_18" "sf_rfmos_18" "ss_rfmos_18" "tt_rfmos_18" ) )
corAddModelFileAndSectionChoices( "tsmcN65" "cor_rfmos_25.scs" '("ff_rfmos_25" "fs_rfmos_25" "sf_rfmos_25" "ss_rfmos_25" "tt_rfmos_25" ) )
corAddModelFileAndSectionChoices( "tsmcN65" "cor_rfmos_33.scs" '("ff_rfmos_33" "fs_rfmos_33" "sf_rfmos_33" "ss_rfmos_33" "tt_rfmos_33" ) )
corAddModelFileAndSectionChoices( "tsmcN65" "cor_std_mos.scs" '("ff" "fs" "sf" "ss" "tt" ) )
corAddModelFileAndSectionChoices( "tsmcN65" "cor_hvt.scs" '("ff_hvt" "fs_hvt" "sf_hvt" "ss_hvt" "tt_hvt" ) )
corAddModelFileAndSectionChoices( "tsmcN65" "cor_lvt.scs" '("ff_lvt" "fs_lvt" "sf_lvt" "ss_lvt" "tt_lvt" ) )
corAddModelFileAndSectionChoices( "tsmcN65" "cor_18.scs" '("ff_18" "fs_18" "sf_18" "ss_18" "tt_18" ) )
corAddModelFileAndSectionChoices( "tsmcN65" "cor_25.scs" '("ff_25" "fs_25" "sf_25" "ss_25" "tt_25" ) )
corAddModelFileAndSectionChoices( "tsmcN65" "cor_25ud18.scs" '("ff_25ud18" "fs_25ud18" "sf_25ud18" "ss_25ud18" "tt_25ud18" ) )
corAddModelFileAndSectionChoices( "tsmcN65" "cor_25od33.scs" '("ff_25od33" "fs_25od33" "sf_25od33" "ss_25od33" "tt_25od33" ) )
corAddModelFileAndSectionChoices( "tsmcN65" "cor_33.scs" '("ff_33" "fs_33" "sf_33" "ss_33" "tt_33" ) )
corAddModelFileAndSectionChoices( "tsmcN65" "cor_na.scs" '("ff_na" "fs_na" "sf_na" "ss_na" "tt_na" ) )
corAddModelFileAndSectionChoices( "tsmcN65" "cor_na25.scs" '("ff_na25" "fs_na25" "sf_na25" "ss_na25" "tt_na25" ) )
corAddModelFileAndSectionChoices( "tsmcN65" "cor_na25od33.scs" '("ff_na25od33" "fs_na25od33" "sf_na25od33" "ss_na25od33" "tt_na25od33" ) )
corAddModelFileAndSectionChoices( "tsmcN65" "cor_na33.scs" '("ff_na33" "fs_na33" "sf_na33" "ss_na33" "tt_na33" ) )
corAddModelFileAndSectionChoices( "tsmcN65" "cor_bip.scs" '("ff_bip" "ss_bip" "tt_bip" ) )
corAddModelFileAndSectionChoices( "tsmcN65" "cor_bip_npn.scs" '("ff_bip_npn" "ss_bip_npn" "tt_bip_npn" ) )
corAddModelFileAndSectionChoices( "tsmcN65" "cor_dio.scs" '("ff_dio" "ss_dio" "tt_dio" ) )
corAddModelFileAndSectionChoices( "tsmcN65" "cor_dio_hvt.scs" '("ff_dio_hvt" "ss_dio_hvt" "tt_dio_hvt" ) )
corAddModelFileAndSectionChoices( "tsmcN65" "cor_dio_lvt.scs" '("ff_dio_lvt" "ss_dio_lvt" "tt_dio_lvt" ) )
corAddModelFileAndSectionChoices( "tsmcN65" "cor_dio_18.scs" '("ff_dio_18" "ss_dio_18" "tt_dio_18" ) )
corAddModelFileAndSectionChoices( "tsmcN65" "cor_dio_25.scs" '("ff_dio_25" "ss_dio_25" "tt_dio_25" ) )
corAddModelFileAndSectionChoices( "tsmcN65" "cor_dio_25ud18.scs" '("ff_dio_25ud18" "ss_dio_25ud18" "tt_dio_25ud18" ) )
corAddModelFileAndSectionChoices( "tsmcN65" "cor_dio_25od33.scs" '("ff_dio_25od33" "ss_dio_25od33" "tt_dio_25od33" ) )
corAddModelFileAndSectionChoices( "tsmcN65" "cor_dio_33.scs" '("ff_dio_33" "ss_dio_33" "tt_dio_33" ) )
corAddModelFileAndSectionChoices( "tsmcN65" "cor_dio_na.scs" '("ff_dio_na" "ss_dio_na" "tt_dio_na" ) )
corAddModelFileAndSectionChoices( "tsmcN65" "cor_dio_na25.scs" '("ff_dio_na25" "ss_dio_na25" "tt_dio_na25" ) )
corAddModelFileAndSectionChoices( "tsmcN65" "cor_dio_na25od33.scs" '("ff_dio_na25od33" "ss_dio_na25od33" "tt_dio_na25od33" ) )
corAddModelFileAndSectionChoices( "tsmcN65" "cor_dio_na33.scs" '("ff_dio_na33" "ss_dio_na33" "tt_dio_na33" ) )
corAddModelFileAndSectionChoices( "tsmcN65" "cor_dio_dnw.scs" '("ff_dio_dnw" "ss_dio_dnw" "tt_dio_dnw" ) )
corAddModelFileAndSectionChoices( "tsmcN65" "cor_dio_esd.scs" '("ff_dio_esd" "ss_dio_esd" "tt_dio_esd" ) )
corAddModelFileAndSectionChoices( "tsmcN65" "cor_res.scs" '("ff_res" "ss_res" "tt_res" ) )
corAddModelFileAndSectionChoices( "tsmcN65" "cor_disres.scs" '("ff_disres" "ss_disres" "tt_disres" ) )
corAddModelFileAndSectionChoices( "tsmcN65" "cor_mos_cap.scs" '("ff_mos_cap" "ss_mos_cap" "tt_mos_cap" ) )
corAddModelFileAndSectionChoices( "tsmcN65" "cor_mos_cap_25.scs" '("ff_mos_cap_25" "ss_mos_cap_25" "tt_mos_cap_25" ) )
corAddModelFileAndSectionChoices( "tsmcN65" "cor_rtmom.scs" '("ff_rtmom" "ss_rtmom" "tt_rtmom" ) )
corAddModelFileAndSectionChoices( "tsmcN65" "cor_mim.scs" '("ff_mim" "ss_mim" "tt_mim" ) )
corAddModelFileAndSectionChoices( "tsmcN65" "cor_rfmvar.scs" '("ff_rfmvar" "ss_rfmvar" "tt_rfmvar" ) )
corAddModelFileAndSectionChoices( "tsmcN65" "cor_rfmvar_25.scs" '("ff_rfmvar_25" "ss_rfmvar_25" "tt_rfmvar_25" ) )
corAddModelFileAndSectionChoices( "tsmcN65" "cor_rfjvar.scs" '("ff_rfjvar" "ss_rfjvar" "tt_rfjvar" ) )
corAddModelFileAndSectionChoices( "tsmcN65" "cor_rfres_sa.scs" '("ff_rfres_sa" "ss_rfres_sa" "tt_rfres_sa" ) )
corAddModelFileAndSectionChoices( "tsmcN65" "cor_rfres_rpo.scs" '("ff_rfres_rpo" "ss_rfres_rpo" "tt_rfres_rpo" ) )
corAddModelFileAndSectionChoices( "tsmcN65" "cor_rfmim.scs" '("ff_rfmim" "ss_rfmim" "tt_rfmim" ) )
corAddModelFileAndSectionChoices( "tsmcN65" "cor_rfrtmom.scs" '("ff_rfrtmom" "ss_rfrtmom" "tt_rfrtmom" ) )
corAddModelFileAndSectionChoices( "tsmcN65" "cor_rfind.scs" '("ff_rfind" "ss_rfind" "tt_rfind" ) )
"""
 
template = """
corAddCorner( "tsmcN65" "{name}" )
corSetCornerGroupVariant( "tsmcN65" "{name}" "cor_rfmos.scs" "{mos_corner}_rfmos" )
corSetCornerGroupVariant( "tsmcN65" "{name}" "cor_rfmos_18.scs" "{mos_corner}_rfmos_18" )
corSetCornerGroupVariant( "tsmcN65" "{name}" "cor_rfmos_25.scs" "{mos_corner}_rfmos_25" )
corSetCornerGroupVariant( "tsmcN65" "{name}" "cor_rfmos_33.scs" "{mos_corner}_rfmos_33" )
corSetCornerGroupVariant( "tsmcN65" "{name}" "cor_std_mos.scs" "{mos_corner}" )
corSetCornerGroupVariant( "tsmcN65" "{name}" "cor_hvt.scs" "{mos_corner}_hvt" )
corSetCornerGroupVariant( "tsmcN65" "{name}" "cor_lvt.scs" "{mos_corner}_lvt" )
corSetCornerGroupVariant( "tsmcN65" "{name}" "cor_18.scs" "{mos_corner}_18" )
corSetCornerGroupVariant( "tsmcN65" "{name}" "cor_25.scs" "{mos_corner}_25" )
corSetCornerGroupVariant( "tsmcN65" "{name}" "cor_25ud18.scs" "{mos_corner}_25ud18" )
corSetCornerGroupVariant( "tsmcN65" "{name}" "cor_25od33.scs" "{mos_corner}_25od33" )
corSetCornerGroupVariant( "tsmcN65" "{name}" "cor_33.scs" "{mos_corner}_33" )
corSetCornerGroupVariant( "tsmcN65" "{name}" "cor_na.scs" "{mos_corner}_na" )
corSetCornerGroupVariant( "tsmcN65" "{name}" "cor_na25.scs" "{mos_corner}_na25" )
corSetCornerGroupVariant( "tsmcN65" "{name}" "cor_na25od33.scs" "{mos_corner}_na25od33" )
corSetCornerGroupVariant( "tsmcN65" "{name}" "cor_na33.scs" "{mos_corner}_na33" )
corSetCornerGroupVariant( "tsmcN65" "{name}" "cor_bip.scs" "{corner}_bip" )
corSetCornerGroupVariant( "tsmcN65" "{name}" "cor_bip_npn.scs" "{corner}_bip_npn" )
corSetCornerGroupVariant( "tsmcN65" "{name}" "cor_dio.scs" "{corner}_dio" )
corSetCornerGroupVariant( "tsmcN65" "{name}" "cor_dio_hvt.scs" "{corner}_dio_hvt" )
corSetCornerGroupVariant( "tsmcN65" "{name}" "cor_dio_lvt.scs" "{corner}_dio_lvt" )
corSetCornerGroupVariant( "tsmcN65" "{name}" "cor_dio_18.scs" "{corner}_dio_18" )
corSetCornerGroupVariant( "tsmcN65" "{name}" "cor_dio_25.scs" "{corner}_dio_25" )
corSetCornerGroupVariant( "tsmcN65" "{name}" "cor_dio_25ud18.scs" "{corner}_dio_25ud18" )
corSetCornerGroupVariant( "tsmcN65" "{name}" "cor_dio_25od33.scs" "{corner}_dio_25od33" )
corSetCornerGroupVariant( "tsmcN65" "{name}" "cor_dio_33.scs" "{corner}_dio_33" )
corSetCornerGroupVariant( "tsmcN65" "{name}" "cor_dio_na.scs" "{corner}_dio_na" )
corSetCornerGroupVariant( "tsmcN65" "{name}" "cor_dio_na25.scs" "{corner}_dio_na25" )
corSetCornerGroupVariant( "tsmcN65" "{name}" "cor_dio_na25od33.scs" "{corner}_dio_na25od33" )
corSetCornerGroupVariant( "tsmcN65" "{name}" "cor_dio_na33.scs" "{corner}_dio_na33" )
corSetCornerGroupVariant( "tsmcN65" "{name}" "cor_dio_dnw.scs" "{corner}_dio_dnw" )
corSetCornerGroupVariant( "tsmcN65" "{name}" "cor_dio_esd.scs" "{corner}_dio_esd" )
corSetCornerGroupVariant( "tsmcN65" "{name}" "cor_res.scs" "{corner}_res" )
corSetCornerGroupVariant( "tsmcN65" "{name}" "cor_disres.scs" "{corner}_disres" )
corSetCornerGroupVariant( "tsmcN65" "{name}" "cor_mos_cap.scs" "{corner}_mos_cap" )
corSetCornerGroupVariant( "tsmcN65" "{name}" "cor_mos_cap_25.scs" "{corner}_mos_cap_25" )
corSetCornerGroupVariant( "tsmcN65" "{name}" "cor_rtmom.scs" "{corner}_rtmom" )
corSetCornerGroupVariant( "tsmcN65" "{name}" "cor_mim.scs" "{corner}_mim" )
corSetCornerGroupVariant( "tsmcN65" "{name}" "cor_rfmvar.scs" "{corner}_rfmvar" )
corSetCornerGroupVariant( "tsmcN65" "{name}" "cor_rfmvar_25.scs" "{corner}_rfmvar_25" )
corSetCornerGroupVariant( "tsmcN65" "{name}" "cor_rfjvar.scs" "{corner}_rfjvar" )
corSetCornerGroupVariant( "tsmcN65" "{name}" "cor_rfres_sa.scs" "{corner}_rfres_sa" )
corSetCornerGroupVariant( "tsmcN65" "{name}" "cor_rfres_rpo.scs" "{corner}_rfres_rpo" )
corSetCornerGroupVariant( "tsmcN65" "{name}" "cor_rfmim.scs" "{corner}_rfmim" )
corSetCornerGroupVariant( "tsmcN65" "{name}" "cor_rfrtmom.scs" "{corner}_rfrtmom" )
corSetCornerGroupVariant( "tsmcN65" "{name}" "cor_rfind.scs" "{corner}_rfind" )
corSetCornerRunTempVal( "tsmcN65" "{name}" {temp} )
"""
  
generic_corners = ['tt', 'ss', 'ff']
mos_corners     = ['tt', 'ss', 'ff', 'sf', 'fs']
res_corners     = ['t', 'w', 'b']
temps           = [25, -25, 75]

user_specified_corners = [

    # Basic corners, omit these since the kit pcf contains these
    #['tt', 'tt', 't',  25],
    #['ss', 'ss', 'w',  75],
    #['ff', 'ff', 'b', -25],

    # FET mismatch, typical otherwise
    ['tt', 'ss', 't',  25],
    ['tt', 'sf', 't',  25],
    ['tt', 'fs', 't',  25],
    ['tt', 'ff', 't',  25]]

for point in user_specified_corners:
    generic_corner = point[0]
    mos_corner     = point[1]
    res_corner     = point[2]
    temp           = point[3]
    name = 'typ_' + mos_corner.lower()
    print template.format(temp='%d'%temp, mos_corner=mos_corner, corner=generic_corner, res_corner=res_corner, name=name)

## Outputs all combinations
#for temp in temps:
#    for generic_corner in generic_corners:
#        for mos_corner in mos_corners:
#            for res_corner in res_corners:
#                name = '%d' % temp + '_' + generic_corner.upper() + '_m' + mos_corner.upper() + '_r' + res_corner.upper()
#                print template.format(temp='%d'%temp, mos_corner=mos_corner, corner=generic_corner, res_corner=res_corner, name=name)
