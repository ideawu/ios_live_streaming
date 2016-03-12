//
//  AVEncoder.m
//  Encoder Demo
//
//  Created by Geraint Davies on 14/01/2013.
//  Copyright (c) 2013 GDCL http://www.gdcl.co.uk/license.htm
//

#import "VideoEncoder.h"
#import "NALUnit.h"
#import "MP4Atom.h"
#import "VideoFile.h"
#import <sys/stat.h>

static unsigned int to_host(unsigned char* p)
{
    return (p[0] << 24) + (p[1] << 16) + (p[2] << 8) + p[3];
}

#define OUTPUT_FILE_SWITCH_POINT (50 * 1024 * 1024)  // 10 MB switch point
#define MAX_FILENAME_INDEX  5                        // filenames "capture1.mp4" wraps at capture5.mp4

// store the calculated POC with a frame ready for timestamp assessment
// (recalculating POC out of order will get an incorrect result)
@interface EncodedFrame : NSObject

- (EncodedFrame*) initWithData:(NSData*) nalus poc:(int)poc;

@property (readonly) int type;
@property int poc;
@property NSData* nalu;

@end

@implementation EncodedFrame

- (EncodedFrame *)initWithData:(NSData*)nalu poc:(int)poc{
    _poc = poc;
    _nalu = nalu;
    return self;
}

- (int)type{
	unsigned char* pNal = (unsigned char*)[_nalu bytes];
	int naltype = pNal[0] & 0x1f;
	return naltype;
}

@end


@interface VideoEncoder ()
{
    // initial writer, used to obtain SPS/PPS from header
    VideoFile* _headerWriter;
    // main encoder/writer
    VideoFile* _writer;
    
    // writer output file (input to our extractor) and monitoring
    NSFileHandle* _inputFile;
    dispatch_queue_t _readQueue;
    dispatch_source_t _readSource;
    
    // index of current file name
    BOOL _swapping;
    int _currentFile;
    int _height;
    int _width;
    
    // param set data
    NSData* _avcC;
    int _lengthSize;
    
    // POC
    POCState _pocState;
    int _prevPOC;
	EncodedFrame *_SEI;
    
    // location of mdat
    BOOL _foundMDAT;
    uint64_t _posMDAT;
    int _bytesToNextAtom;
    BOOL _needParams;
    
    // tracking if NALU is next frame
    int _prev_nal_idc;
    int _prev_nal_type;
    // array of NSData comprising a single frame. each data is one nalu with no start code
    NSMutableArray* _pendingNALU;
    
    // FIFO for frame times
    NSMutableArray* _times;
    
    // FIFO for frames awaiting time assigment
    NSMutableArray* _frames;
    
    encoder_handler_t _outputBlock;
	void (^_paramsBlock)(NSData *sps, NSData *pps);
    
    // estimate bitrate over first second
    int _bitspersecond;
    double _firstpts;
}

@property (readonly, atomic) int bitspersecond;
@property int bitrate;
- (void) initForHeight:(int) height andWidth:(int) width;

@end

@implementation VideoEncoder

@synthesize bitspersecond = _bitspersecond;

+ (VideoEncoder*)encoderForHeight:(int) height andWidth:(int) width bitrate:(int)bitrate
{
    VideoEncoder* enc = [VideoEncoder alloc];
	enc.bitrate = bitrate;
    [enc initForHeight:height andWidth:width];
    return enc;
}

- (NSString*) makeFilename
{
    NSString* filename = [NSString stringWithFormat:@"m%d.mp4", _currentFile];
    NSString* path = [NSTemporaryDirectory() stringByAppendingPathComponent:filename];
    return path;
}
- (void) initForHeight:(int)height andWidth:(int)width
{
    _height = height;
    _width = width;
    NSString* path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"m.mp4"];
    _headerWriter = [VideoFile videoForPath:path Height:height andWidth:width bitrate:_bitrate];
    _times = [NSMutableArray arrayWithCapacity:10];
	
    // swap between 3 filenames
    _currentFile = 1;
    _writer = [VideoFile videoForPath:[self makeFilename] Height:height andWidth:width bitrate:_bitrate];

	_frames = [NSMutableArray arrayWithCapacity:2];
}

- (void) encodeWithBlock:(encoder_handler_t) block onParams:(void (^)(NSData *sps, NSData *pps))paramsHandler
{
    _outputBlock = block;
    _paramsBlock = paramsHandler;
    _needParams = YES;
	_pendingNALU = [NSMutableArray arrayWithCapacity:2];
    _firstpts = -1;
    _bitspersecond = 0;
}

- (BOOL) parseParams:(NSString*) path
{
    NSFileHandle* file = [NSFileHandle fileHandleForReadingAtPath:path];
    struct stat s;
    fstat([file fileDescriptor], &s);
    MP4Atom* movie = [MP4Atom atomAt:0 size:(int)s.st_size type:(OSType)('file') inFile:file];
    MP4Atom* moov = [movie childOfType:(OSType)('moov') startAt:0];
    MP4Atom* trak = nil;
    if (moov != nil)
    {
        for (;;)
        {
            trak = [moov nextChild];
            if (trak == nil)
            {
                break;
            }
            
            if (trak.type == (OSType)('trak'))
            {
                MP4Atom* tkhd = [trak childOfType:(OSType)('tkhd') startAt:0];
                NSData* verflags = [tkhd readAt:0 size:4];
                unsigned char* p = (unsigned char*)[verflags bytes];
                if (p[3] & 1)
                {
                    break;
                }
                else
                {
                    tkhd = nil;
                }
            }
        }
    }
    MP4Atom* stsd = nil;
    if (trak != nil)
    {
        MP4Atom* media = [trak childOfType:(OSType)('mdia') startAt:0];
        if (media != nil)
        {
            MP4Atom* minf = [media childOfType:(OSType)('minf') startAt:0];
            if (minf != nil)
            {
                MP4Atom* stbl = [minf childOfType:(OSType)('stbl') startAt:0];
                if (stbl != nil)
                {
                    stsd = [stbl childOfType:(OSType)('stsd') startAt:0];
                }
            }
        }
    }
    if (stsd != nil)
    {
        MP4Atom* avc1 = [stsd childOfType:(OSType)('avc1') startAt:8];
        if (avc1 != nil)
        {
            MP4Atom* esd = [avc1 childOfType:(OSType)('avcC') startAt:78];
            if (esd != nil)
            {
                // this is the avcC record that we are looking for
                _avcC = [esd readAt:0 size:(int)esd.length];
                if (_avcC != nil)
                {
                    // extract size of length field
                    unsigned char* p = (unsigned char*)[_avcC bytes];
                    _lengthSize = (p[4] & 3) + 1;
                    
                    avcCHeader avc((const BYTE*)[_avcC bytes], (int)[_avcC length]);
                    _pocState.SetHeader(&avc);
                    
                    return YES;
                }
            }
        }
    }
    return NO;
}

- (void) onParamsCompletion
{
    // the initial one-frame-only file has been completed
    // Extract the avcC structure and then start monitoring the
    // main file to extract video from the mdat chunk.
    if ([self parseParams:_headerWriter.path])
    {
        if (_paramsBlock){
			avcCHeader avcC((const BYTE*)[_avcC bytes], (int)[_avcC length]);
			//	SeqParamSet seqParams;
			//	seqParams.Parse(avcC.sps());
			NSData *sps = [NSData dataWithBytes:avcC.sps()->Start() length:avcC.sps()->Length()];
			NSData *pps = [NSData dataWithBytes:avcC.pps()->Start() length:avcC.pps()->Length()];
            _paramsBlock(sps, pps);
        }
        _headerWriter = nil;
        _swapping = NO;
        _inputFile = [NSFileHandle fileHandleForReadingAtPath:_writer.path];
        _readQueue = dispatch_queue_create("VideoEncoder.read", DISPATCH_QUEUE_SERIAL);
        
        _readSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, [_inputFile fileDescriptor], 0, _readQueue);
        dispatch_source_set_event_handler(_readSource, ^{
            [self onFileUpdate];
        });
        dispatch_resume(_readSource);
    }
}

- (void) encodeSampleBuffer:(CMSampleBufferRef) sampleBuffer{
    @synchronized(self)
    {
        if (_needParams){
            // the avcC record is needed for decoding and it's not written to the file until
            // completion. We get round that by writing the first frame to two files; the first
            // file (containing only one frame) is then finished, so we can extract the avcC record.
            // Only when we've got that do we start reading from the main file.
            _needParams = NO;
            if ([_headerWriter encodeFrame:sampleBuffer]){
                [_headerWriter finishWithCompletionHandler:^{
                    [self onParamsCompletion];
                }];
            }
        }
    }
    double prestime = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer));
    NSNumber* pts = [NSNumber numberWithDouble:prestime];
    
    @synchronized(_times)
    {
        [_times addObject:pts];
    }
    @synchronized(self)
    {
        // switch output files when we reach a size limit
        // to avoid runaway storage use.
        if (!_swapping)
        {
            struct stat st;
            fstat([_inputFile fileDescriptor], &st);
            if (st.st_size > OUTPUT_FILE_SWITCH_POINT){
                _swapping = YES;
                VideoFile* oldVideo = _writer;
                
                // construct a new writer to the next filename
                if (++_currentFile > MAX_FILENAME_INDEX){
                    _currentFile = 1;
                }
                NSLog(@"Swap to file %d", _currentFile);
                _writer = [VideoFile videoForPath:[self makeFilename] Height:_height andWidth:_width bitrate:_bitrate];
                
                
                // to do this seamlessly requires a few steps in the right order
                // first, suspend the read source
                dispatch_source_cancel(_readSource);
                // execute the next step as a block on the same queue, to be sure the suspend is done
                dispatch_async(_readQueue, ^{
                    // finish the file, writing moov, before reading any more from the file
                    // since we don't yet know where the mdat ends
                    _readSource = nil;
                    [oldVideo finishWithCompletionHandler:^{
                        [self swapFiles:oldVideo.path];
                    }];
                });
            }
        }
        [_writer encodeFrame:sampleBuffer];
    }
}

- (void) swapFiles:(NSString*) oldPath
{
    // save current position
    uint64_t pos = [_inputFile offsetInFile];
    
    // re-read mdat length
    [_inputFile seekToFileOffset:_posMDAT];
    NSData* hdr = [_inputFile readDataOfLength:4];
    unsigned char* p = (unsigned char*) [hdr bytes];
    int lenMDAT = to_host(p);

    // extract nalus from saved position to mdat end
    uint64_t posEnd = _posMDAT + lenMDAT;
    uint32_t cRead = (uint32_t)(posEnd - pos);
    [_inputFile seekToFileOffset:pos];
    [self readAndDeliver:cRead];
    
    // close and remove file
    [_inputFile closeFile];
    _foundMDAT = false;
    _bytesToNextAtom = 0;
    [[NSFileManager defaultManager] removeItemAtPath:oldPath error:nil];
    
    
    // open new file and set up dispatch source
    _inputFile = [NSFileHandle fileHandleForReadingAtPath:_writer.path];
    _readSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, [_inputFile fileDescriptor], 0, _readQueue);
    dispatch_source_set_event_handler(_readSource, ^{
        [self onFileUpdate];
    });
    dispatch_resume(_readSource);
    _swapping = NO;
}


- (void) readAndDeliver:(uint32_t) cReady
{
    // Identify the individual NALUs and extract them
    while (cReady > _lengthSize)
    {
        NSData* lenField = [_inputFile readDataOfLength:_lengthSize];
        cReady -= _lengthSize;
        unsigned char* p = (unsigned char*) [lenField bytes];
        unsigned int lenNALU = to_host(p);
        
        if (lenNALU > cReady)
        {
            // whole NALU not present -- seek back to start of NALU and wait for more
            [_inputFile seekToFileOffset:[_inputFile offsetInFile] - 4];
            break;
        }
        NSData* nalu = [_inputFile readDataOfLength:lenNALU];
        cReady -= lenNALU;
        
        [self onNALU:nalu];
    }
}

- (void) onFileUpdate
{
    // called whenever there is more data to read in the main encoder output file.
    
    struct stat s;
    fstat([_inputFile fileDescriptor], &s);
    int cReady = (int)(s.st_size - [_inputFile offsetInFile]);
    
    // locate the mdat atom if needed
    while (!_foundMDAT && (cReady > 8))
    {
        if (_bytesToNextAtom == 0)
        {
            NSData* hdr = [_inputFile readDataOfLength:8];
            cReady -= 8;
            unsigned char* p = (unsigned char*) [hdr bytes];
            int lenAtom = to_host(p);
            unsigned int nameAtom = to_host(p+4);
            if (nameAtom == (unsigned int)('mdat'))
            {
                _foundMDAT = true;
                _posMDAT = [_inputFile offsetInFile] - 8;
            }
            else
            {
                _bytesToNextAtom = lenAtom - 8;
            }
        }
        if (_bytesToNextAtom > 0)
        {
            int cThis = cReady < _bytesToNextAtom ? cReady :_bytesToNextAtom;
            _bytesToNextAtom -= cThis;
            [_inputFile seekToFileOffset:[_inputFile offsetInFile]+cThis];
            cReady -= cThis;
        }
    }
    if (!_foundMDAT)
    {
        return;
    }
    
    // the mdat must be just encoded video.
    [self readAndDeliver:cReady];
}

//- (void) deliverFrame: (NSArray*) frame withTime:(double) pts poc:(int)poc
//{
//
//    if (_firstpts < 0)
//    {
//        _firstpts = pts;
//    }
//    if ((pts - _firstpts) < 1)
//    {
//        int bytes = 0;
//        for (NSData* data in frame)
//        {
//            bytes += [data length];
//        }
//        _bitspersecond += (bytes * 8);
//    }
// 
//    if (_outputBlock != nil)
//    {
//        _outputBlock(frame, pts);
//    }
//    
//}
//
//- (void) processStoredFrames
//{
//	// 处理reordering相关
//	EncodedFrame *first = nil;
//    // first has the last timestamp and rest use up timestamps from the start
//    int n = 0;
//    for (EncodedFrame* f in _frames){
//        int index = 0;
//        if (n == 0){
//            index = (int) [_frames count] - 1;
//        }else{
//            index = n-1;
//        }
//        double pts = 0;
//        @synchronized(_times){
//            if ([_times count] > 0){
//                pts = [_times[index] doubleValue];
//            }
//        }
//		f.pts = pts;
//		if(n == 0){
//			first = f;
//		}else{
//			[self deliverFrame:f.frame withTime:pts poc:f.poc];
//		}
//        n++;
//    }
//    @synchronized(_times){
//        [_times removeObjectsInRange:NSMakeRange(0, [_frames count])];
//    }
//    [_frames removeAllObjects];
//	if(first){
//		[self deliverFrame:first.frame withTime:first.pts poc:first.poc];
//	}
//}

//- (void) onEncodedFrame
//{
//    int poc = 0;
//    for (NSData* d in _pendingNALU){
//        NALUnit nal((const BYTE*)[d bytes], (int)[d length]);
//        if (_pocState.GetPOC(&nal, &poc)){
//            break;
//        }
//    }
//    
//    if (poc == 0){
//		if(_frames.count > 0){
//			NSLog(@"process stored");
//			[self processStoredFrames];
//		}else{
//			double pts = 0;
//			int index = 0;
//			@synchronized(_times)
//			{
//				if ([_times count] > 0){
//					pts = [_times[index] doubleValue];
//					[_times removeObjectAtIndex:index];
//				}
//			}
//			for(NSData *data in _pendingNALU){
//				unsigned char* pNal = (unsigned char*)[data bytes];
//				int naltype = pNal[0] & 0x1f;
//				if(naltype == 5 || naltype == 6){
//					log_debug(@"TYPE %d", naltype);
//				}
//			}
//			NSLog(@"delever");
//			[self deliverFrame:_pendingNALU withTime:pts poc:0];
//		}
//		[_pendingNALU removeAllObjects];
//        _prevPOC = 0;
//    }else{
//		//NSLog(@"poc: %d", poc);
//        EncodedFrame* f = [[EncodedFrame alloc] initWithData:_pendingNALU andPOC:poc];
//        if (poc > _prevPOC){
//            // all pending frames come before this, so share out the
//            // timestamps in order of POC
//            [self processStoredFrames];
//            _prevPOC = poc;
//        }
//		for(NSData *data in f.frame){
//			unsigned char* pNal = (unsigned char*)[data bytes];
//			int naltype = pNal[0] & 0x1f;
//			if(naltype == 5 || naltype == 6){
//				log_debug(@"TYPE %d", naltype);
//			}
//		}
//        [_frames addObject:f];
//    }
//}

- (void)notifyFrame:(EncodedFrame *)frame{
	double pts = 0;
	@synchronized(_times){
		if ([_times count] > 0){
			pts = [_times[0] doubleValue];
			[_times removeObjectAtIndex:0];
		}else{
			log_debug("");
		}
	}
	if(frame.type == 5 && _SEI){
		log_debug(@"notify type: %d, pts: %f", _SEI.type, pts);
		_outputBlock(_SEI.nalu, pts);
		_SEI = nil;
	}
	log_debug(@"notify type: %d, pts: %f, poc: %d", frame.type, pts, frame.poc);
	_outputBlock(frame.nalu, pts);
}

// combine multiple NALUs into a single frame, and in the process, convert to BSF
// by adding 00 00 01 startcodes before each NALU.
- (void)onNALU:(NSData*)nalu{
	int poc = 0;
	NALUnit nal((const BYTE*)[nalu bytes], (int)[nalu length]);
	if (_pocState.GetPOC(&nal, &poc)){
		//
	}

	EncodedFrame *frame = [[EncodedFrame alloc] initWithData:nalu poc:poc];
//	log_debug(@"read type: %d, poc: %d", frame.type, frame.poc);
	if(frame.type == 6){
		_SEI = frame;
		return;
	}

	if(poc == 0){
		[self processStoredFrames];
		[self notifyFrame:frame];
		_prevPOC = 0;
	}else{
		if(poc > _prevPOC){
			[self processStoredFrames];
			_prevPOC = poc;
		}
		[_frames addObject:frame];
	}

}

- (void)processStoredFrames{
	if(_frames.count == 0){
		return;
	}
	// first has the last timestamp and rest use up timestamps from the start
	// 处理reordering相关
	for(int i=1; i<_frames.count; i++){
		[self notifyFrame:_frames[i]];
	}
	[self notifyFrame:_frames[0]];
	[_frames removeAllObjects];
}

- (NSData*) getConfigData{
    return [_avcC copy];
}

- (void) shutdown{
    @synchronized(self){
        _readSource = nil;
        if (_headerWriter){
            [_headerWriter finishWithCompletionHandler:^{
                _headerWriter = nil;
            }];
        }
        if (_writer){
            [_writer finishWithCompletionHandler:^{
                _writer = nil;
            }];
        }
        // !! wait for these to finish before returning and delete temp files
    }
}

@end
//    if (_pendingNALU.count > 0){
//        NALUnit nal(pNal, (int)[nalu length]);
//
//        // we have existing data —is this the same frame?
//        // typically there are a couple of NALUs per frame in iOS encoding.
//        // This is not general-purpose: it assumes that arbitrary slice ordering is not allowed.
//        BOOL bNew = NO;
//
//        // sei and param sets go with following nalu
//        if (_prev_nal_type < 6){
//            if (naltype >= 6){
//                bNew = YES;
//            }else if ((idc != _prev_nal_idc) && ((idc == 0) || (_prev_nal_idc == 0))){
//                bNew = YES;
//            }else if ((naltype != _prev_nal_type) && (naltype == 5)){
//                bNew = YES;
//            }else if ((naltype >= 1) && (naltype <= 5)){
//                nal.Skip(8);
//                int first_mb = (int)nal.GetUE();
//                if (first_mb == 0){
//                    bNew = YES;
//                }
//            }
//        }
//
//        if (bNew){
//            [self onEncodedFrame];
//			[_pendingNALU removeAllObjects];
//        }
//    }
//    _prev_nal_type = naltype;
//    _prev_nal_idc = idc;
//    [_pendingNALU addObject:nalu];
