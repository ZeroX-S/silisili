#pragma once

// Sailfish OS 5.0's userspace videodev2.h predates constants already exposed
// by the Pixel 3a/3a XL Qualcomm Venus driver. FFmpeg 5.1 uses these upstream
// UAPI names to compile its generic V4L2-M2M decoder. The numeric values below
// match Linux UAPI and the fourcc values returned by VIDIOC_ENUM_FMT on the
// target device; no private kernel structure is copied into the application.
#include <linux/videodev2.h>

#ifndef V4L2_BUF_FLAG_LAST
#define V4L2_BUF_FLAG_LAST 0x00100000
#endif

#ifndef V4L2_PIX_FMT_HEVC
#define V4L2_PIX_FMT_HEVC v4l2_fourcc('H', 'E', 'V', 'C')
#endif

#ifndef V4L2_PIX_FMT_VP9
#define V4L2_PIX_FMT_VP9 v4l2_fourcc('V', 'P', '9', '0')
#endif
