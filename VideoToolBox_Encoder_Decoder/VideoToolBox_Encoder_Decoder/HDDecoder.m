//
//  HDDecoder.m
//  VideoToolBox_Encoder_Decoder
//
//  Created by 黄世平 on 2021/8/28.
//

#import "HDDecoder.h"

@interface HDDecoder()

- (BOOL)initH264Decoder;

@end

@implementation HDDecoder

-(instancetype)initWithDecodeConfig:(DecoderConfig)config {
    if (self = [super init]) {
        _width = config.width;
        _height = config.height;
        _cvPixelFormatType = config.cvPixelFormatType;
    }
    return self;
}

-(void)startDecoder {
    
}

-(void)stopDecoder {
    if(_decoderSession) {
        VTDecompressionSessionInvalidate(_decoderSession);
        CFRelease(_decoderSession);
        _decoderSession = NULL;
    }
    if(_decoderFormatDescription) {
        CFRelease(_decoderFormatDescription);
        _decoderFormatDescription = NULL;
    }
    if (_sps) {
        free(_sps);
    }
    if (_pps) {
        free(_pps);
    }
    _ppsSize = _spsSize = 0;
}

-(void)decodeNALU:(uint8_t*)frame length:(uint32_t)length {
    /**
     *获取NALU Type
     */
    int nalu_type = (frame[4] & 0x1F);
    CVPixelBufferRef pixelBuffer = NULL;
    
    /**
     *填充nalu size 去掉start code 替换成nalu size
     */
    uint32_t nalSize = (uint32_t)(length - 4);
    uint8_t *pNalSize = (uint8_t*)(&nalSize);
    frame[0] = *(pNalSize + 3);
    frame[1] = *(pNalSize + 2);
    frame[2] = *(pNalSize + 1);
    frame[3] = *(pNalSize);
  
    switch (nalu_type) {
        case 0x05:
            /**
             *关键帧
             */
            if([self initH264Decoder]) {
                pixelBuffer = [self decode:frame size:length];
            }
            break;
        case 0x07: {
            /**
             * sps
             */
            _spsSize = length - 4;
            _sps = malloc(_spsSize);
            memcpy(_sps, &frame[4], _spsSize);
            break;
        }
        case 0x08: {
            /**
             *pps
             */
            _ppsSize = length - 4;
            _pps = malloc(_ppsSize);
            memcpy(_pps, &frame[4], _ppsSize);
            break;
        }
        default: {
            /**
             *B/P frame
             */
            if([self initH264Decoder]) {
                pixelBuffer = [self decode:frame size:length];
            }
            break;
        }
    }
}

-(void)setH264Delegate:(id<H264DecodeDataDelegate> _Nonnull)h264Delegate {
    self.h264Delegate = h264Delegate;
}

/**
 *解码帧数据
 */
- (CVPixelBufferRef)decode:(uint8_t *)frame size:(uint32_t)frameSize {
    CVPixelBufferRef outputPixelBuffer = NULL;
    CMBlockBufferRef blockBuffer = NULL;
    /**
     *创建CMBlockBufferRef
     */
    OSStatus status = CMBlockBufferCreateWithMemoryBlock(NULL,
                                                         (void *)frame,
                                                         frameSize,
                                                         kCFAllocatorNull,
                                                         NULL,
                                                         0,
                                                         frameSize,
                                                         FALSE,
                                                         &blockBuffer);
    if (status == kCMBlockBufferNoErr) {
        
        CMSampleBufferRef sampleBuffer = NULL;
        const size_t sampleSizeArray[] = {frameSize};
        
        //创建sampleBuffer
        status = CMSampleBufferCreateReady(kCFAllocatorDefault,
                                           blockBuffer,
                                           _decoderFormatDescription ,
                                           1, 0, NULL, 1, sampleSizeArray,
                                           &sampleBuffer);
        
        if (status == kCMBlockBufferNoErr && sampleBuffer) {
            VTDecodeFrameFlags flags = 0;
            VTDecodeInfoFlags flagOut = 0;
            //CMSampleBufferRef丢进去解码
            OSStatus decodeStatus = VTDecompressionSessionDecodeFrame(_decoderSession,
                                                                      sampleBuffer,
                                                                      flags,
                                                                      &outputPixelBuffer,
                                                                      &flagOut);
            
            if(decodeStatus == kVTInvalidSessionErr) {
                NSLog(@"IOS8VT: Invalid session, reset decoder session");
            } else if(decodeStatus == kVTVideoDecoderBadDataErr) {
                NSLog(@"IOS8VT: decode failed status=%d(Bad data)", decodeStatus);
            } else if(decodeStatus != noErr) {
                NSLog(@"IOS8VT: decode failed status=%d", decodeStatus);
            }
            CFRelease(sampleBuffer);
        }
         CFRelease(blockBuffer);
    }
    /**
     *返回pixelBuffer数据
     */
    return outputPixelBuffer;
}

/**
 *解码回调
 */
static void didDeCompress( void *decompressionOutputRefCon, void *sourceFrameRefCon, OSStatus status, VTDecodeInfoFlags infoFlags, CVImageBufferRef pixelBuffer, CMTime presentationTimeStamp, CMTime presentationDuration ){
    CVPixelBufferRef *outputPixelBuffer = (CVPixelBufferRef *)sourceFrameRefCon;
    /**
     *持有pixelBuffer数据，否则会被释放
     */
    *outputPixelBuffer = CVPixelBufferRetain(pixelBuffer);
    HDDecoder *decoder = (__bridge HDDecoder *)decompressionOutputRefCon;
    if (decoder.h264Delegate) {
        [decoder.h264Delegate gotDecodedFrame:pixelBuffer];
    }
}

- (BOOL)initH264Decoder {
    if(_decoderSession) {
        return YES;
    }
    
    const uint8_t* const parameterSetPointers[2] = { _sps, _pps };
    const size_t parameterSetSizes[2] = { _spsSize, _ppsSize };
    
    /**
     *用sps 和pps 实例化_decoderFormatDescription
     */
    OSStatus status = CMVideoFormatDescriptionCreateFromH264ParameterSets(kCFAllocatorDefault,
                                                                          2, //参数个数
                                                                          parameterSetPointers,
                                                                          parameterSetSizes,
                                                                          4, //nal startcode开始的size
                                                                          &_decoderFormatDescription);
    
    if(status == noErr) {
        NSDictionary* destinationPixelBufferAttributes = @{
                                                           (id)kCVPixelBufferPixelFormatTypeKey : [NSNumber numberWithInt:_cvPixelFormatType],
                                                           (id)kCVPixelBufferWidthKey : [NSNumber numberWithInt:_width],
                                                           (id)kCVPixelBufferHeightKey : [NSNumber numberWithInt:_height],
                                                           //这里宽高和编码反的 两倍关系
                                                           (id)kCVPixelBufferOpenGLCompatibilityKey : [NSNumber numberWithBool:YES]
                                                           };

        
        
        VTDecompressionOutputCallbackRecord callBackRecord;
        callBackRecord.decompressionOutputCallback = didDeCompress;
        callBackRecord.decompressionOutputRefCon = (__bridge void *)self;
        status = VTDecompressionSessionCreate(kCFAllocatorDefault,
                                              _decoderFormatDescription,
                                              NULL,
                                              (__bridge CFDictionaryRef)destinationPixelBufferAttributes,
                                              &callBackRecord,
                                              &_decoderSession);
        VTSessionSetProperty(_decoderSession, kVTDecompressionPropertyKey_ThreadCount, (__bridge CFTypeRef)[NSNumber numberWithInt:1]);
        VTSessionSetProperty(_decoderSession, kVTDecompressionPropertyKey_RealTime, kCFBooleanTrue);
    } else {
        NSLog(@"IOS8VT: reset decoder session failed status=%d", status);
        return NO;
    }
    
    return YES;
}

@end
