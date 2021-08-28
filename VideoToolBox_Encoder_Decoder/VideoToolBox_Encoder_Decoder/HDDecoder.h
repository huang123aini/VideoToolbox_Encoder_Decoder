//
//  HDDecoder.h
//  VideoToolBox_Encoder_Decoder
//
//  Created by 黄世平 on 2021/8/28.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <VideoToolbox/VideoToolbox.h>

NS_ASSUME_NONNULL_BEGIN

@protocol H264DecodeDataDelegate <NSObject>

@optional
-(void)gotDecodedFrame:(CVImageBufferRef)imageBuffer;

@end

typedef struct DecoderConfig_{
    int width;
    int height;
    int cvPixelFormatType;
    /**
     *硬解必须是 kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange或者是kCVPixelFormatType_420YpCbCr8Planar
     *因为iOS是  nv12  其他是nv21
     */
}DecoderConfig;

@interface HDDecoder : NSObject

/**
 *解码session
 */
@property VTDecompressionSessionRef decoderSession;

/**
 *解码的宽
 */
@property int width;

/**
 *解码的高
 */
@property int height;

/**
 *解码的像素格式类型
 */
@property int cvPixelFormatType;

/**
 *解码Format 封装了sps和pps
 */
@property CMVideoFormatDescriptionRef decoderFormatDescription;

/**
 *序列参数集
 */
@property uint8_t* sps;

@property NSInteger spsSize;

/**
 *图像参数集
 */
@property uint8_t* pps;

@property NSInteger ppsSize;

/**
 *解码数据回调代理
 */
@property (nonatomic) id<H264DecodeDataDelegate> h264Delegate;

-(instancetype)initWithDecodeConfig:(DecoderConfig)config;

-(void)stopDecoder;

-(void)decodeNALU:(uint8_t*)frame length:(uint32_t)length;

-(void)setH264Delegate:(id<H264DecodeDataDelegate> _Nonnull)h264Delegate;
@end

NS_ASSUME_NONNULL_END
