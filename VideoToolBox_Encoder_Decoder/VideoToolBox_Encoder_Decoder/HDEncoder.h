//
//  HDEncoder.h
//  VideoToolBox_Encoder_Decoder
//
//  Created by 黄世平 on 2021/8/28.
//

#import <Foundation/Foundation.h>
#import <VideoToolbox/VideoToolbox.h>

NS_ASSUME_NONNULL_BEGIN

typedef struct EncoderConfig_ {
    int width;
    int height;
    int gop;
    int wantFps;
    int bitRate;
    int bitRateLimit;
    
}EncoderConfig;

@protocol EncoderDataDelegate <NSObject>

@optional
-(void)encodeData:(NSData*)data;

@end

@interface HDEncoder : NSObject

#pragma mark --编码参数相关---
/**
 *编码视频宽
 */
@property int width;

/**
 *编码视频高
 */
@property int height;

/**
 *编码视频gop
 */
@property int gop;

/**
 *期望帧率
 */
@property int wantFps;

/**
 *编码码率
 */
@property int bitRate;

/**
 *码率上限值
 */
@property int bitRateLimit;

/**
 *编码队列
 */
@property dispatch_queue_t encodeQueue;

/**
 *编码session
 */
@property VTCompressionSessionRef encodingSession;


#pragma mark --编码过程相关---

@property int frameNum;

@property (nonatomic) id encodeDataDelegate;

-(instancetype)initWithEncoderConfig:(EncoderConfig)config;

/**
 *开启编码器
 */
-(void)startEncoder;

/**
 *关闭编码器
 */
-(void)stopEncoder;

/**
 *编码帧
 */
-(void)encoder:(CMSampleBufferRef)samplebuffer;

/**
 *设置编码后数据处理代理
 */
-(void)setEncodeDataDelegate:(id _Nonnull)encodeDataDelegate;

@end

NS_ASSUME_NONNULL_END
