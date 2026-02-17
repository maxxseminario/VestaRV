////////////////////////////////////////////////////////////////////////////
//                            **** LZW-AB ****                            //
//               Adjusted Binary LZW Compressor/Decompressor              //
//                     Copyright (c) 2016 David Bryant                    //
//                           All Rights Reserved                          //
//      Distributed under the BSD Software License (see license.txt)      //
////////////////////////////////////////////////////////////////////////////

#pragma once

#ifdef __cplusplus
extern "C" {
#endif

/** External Function Declarations **/
int lzw_compress(unsigned char *src, unsigned int src_bytes, unsigned char *dst, unsigned int dst_max_bytes);
int lzw_decompress(unsigned char *src, unsigned int src_bytes, unsigned char *dst, unsigned int dst_max_bytes);



#ifdef __cplusplus
}
#endif
