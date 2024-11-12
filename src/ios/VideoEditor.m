//
//  VideoEditor.m
//
//  Created by Josh Bavari on 01-14-2014
//  Modified by Ross Martin on 01-29-2015
//

#import <Cordova/CDV.h>
#import "VideoEditor.h"
#import "SDAVAssetExportSession.h"

@interface VideoEditor ()

@end

@implementation VideoEditor

/**
 * transcodeVideo
 *
 * Transcodes a video
 *
 * ARGUMENTS
 * =========
 *
 * fileUri              - path to input video
 * outputFileName       - output file name
 * outputFileType       - output file type
 * saveToLibrary        - save to gallery
 * maintainAspectRatio  - make the output aspect ratio match the input video
 * width                - width for the output video
 * height               - height for the output video
 * videoBitrate         - video bitrate for the output video in bits
 * audioChannels        - number of audio channels for the output video
 * audioSampleRate      - sample rate for the audio (samples per second)
 * audioBitrate         - audio bitrate for the output video in bits
 *
 * RESPONSE
 * ========
 *
 * outputFilePath - path to output file
 *
 * @param CDVInvokedUrlCommand command
 * @return void
 */
- (void) transcodeVideo:(CDVInvokedUrlCommand*)command
{
    NSDictionary* options = [command.arguments objectAtIndex:0];

    if ([options isKindOfClass:[NSNull class]]) {
        options = [NSDictionary dictionary];
    }

    NSString *inputFilePath = [options objectForKey:@"fileUri"];
    NSURL *inputFileURL = [self getURLFromFilePath:inputFilePath];
    NSString *videoFileName = [options objectForKey:@"outputFileName"];
    CDVOutputFileType outputFileType = ([options objectForKey:@"outputFileType"]) ? [[options objectForKey:@"outputFileType"] intValue] : MPEG4;
    BOOL optimizeForNetworkUse = ([options objectForKey:@"optimizeForNetworkUse"]) ? [[options objectForKey:@"optimizeForNetworkUse"] intValue] : NO;
    BOOL saveToPhotoAlbum = [options objectForKey:@"saveToLibrary"] ? [[options objectForKey:@"saveToLibrary"] boolValue] : YES;
    BOOL maintainAspectRatio = [options objectForKey:@"maintainAspectRatio"] ? [[options objectForKey:@"maintainAspectRatio"] boolValue] : YES;
    float width = [[options objectForKey:@"width"] floatValue];
    float height = [[options objectForKey:@"height"] floatValue];
    int deleteInputFile = [options objectForKey:@"deleteInputFile"] ? [[options objectForKey:@"deleteInputFile"] boolValue] : YES;

    NSString *stringOutputFileType = nil;
    NSString *outputExtension = nil;

    switch (outputFileType) {
        case QUICK_TIME:
            stringOutputFileType = AVFileTypeQuickTimeMovie;
            outputExtension = @".mov";
            break;
        case M4A:
            stringOutputFileType = AVFileTypeAppleM4A;
            outputExtension = @".m4a";
            break;
        case M4V:
            stringOutputFileType = AVFileTypeAppleM4V;
            outputExtension = @".m4v";
            break;
        case MPEG4:
        default:
            stringOutputFileType = AVFileTypeMPEG4;
            outputExtension = @".mp4";
            break;
    }

    // Check if the video can be saved to photo album before going further
    if (saveToPhotoAlbum && !UIVideoAtPathIsCompatibleWithSavedPhotosAlbum([inputFileURL path]))
    {
        NSString *error = @"Video cannot be saved to photo album";
        [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:error ] callbackId:command.callbackId];
        return;
    }

    AVURLAsset *avAsset = [AVURLAsset URLAssetWithURL:inputFileURL options:nil];

    NSString *cacheDir = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) objectAtIndex:0];
    NSString *outputPath = [NSString stringWithFormat:@"%@/%@%@", cacheDir, videoFileName, outputExtension];
    NSURL *outputURL = [NSURL fileURLWithPath:outputPath];

    NSArray *tracks = [avAsset tracksWithMediaType:AVMediaTypeVideo];
    if ([tracks count] == 0) {
        NSString *error = @"No video tracks found in the asset";
        [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:error ] callbackId:command.callbackId];
        return;
    }

    AVAssetTrack *track = [tracks objectAtIndex:0];
    CGSize mediaSize = track.naturalSize;
    CGAffineTransform preferredTransform = track.preferredTransform;

    float videoWidth = mediaSize.width;
    float videoHeight = mediaSize.height;
    int newWidth;
    int newHeight;

    // Adjust for orientation
    if (preferredTransform.b == 1.0 && preferredTransform.c == -1.0) {
        // Portrait
        float temp = videoWidth;
        videoWidth = videoHeight;
        videoHeight = temp;
    }

    if (maintainAspectRatio) {
        float aspectRatio = videoWidth / videoHeight;

        if (width && height) {
            if (videoWidth > videoHeight) {
                // Landscape
                newWidth = width;
                newHeight = width / aspectRatio;
            } else {
                // Portrait
                newHeight = height;
                newWidth = height * aspectRatio;
            }
        } else {
            newWidth = videoWidth;
            newHeight = videoHeight;
        }

        // Ensure dimensions are even numbers
        newWidth = ((int)newWidth) & ~1;
        newHeight = ((int)newHeight) & ~1;
    } else {
        newWidth = (width && height) ? width : videoWidth;
        newHeight = (width && height) ? height : videoHeight;
    }

    NSLog(@"input videoWidth: %f", videoWidth);
    NSLog(@"input videoHeight: %f", videoHeight);
    NSLog(@"output newWidth: %d", newWidth);
    NSLog(@"output newHeight: %d", newHeight);

    // Choose an appropriate preset
    NSString *presetName = nil;
    NSArray *compatiblePresets = [AVAssetExportSession exportPresetsCompatibleWithAsset:avAsset];
    if([compatiblePresets containsObject:AVAssetExportPreset640x480]) {
        presetName = AVAssetExportPreset640x480;
    } else if([compatiblePresets containsObject:AVAssetExportPresetHighestQuality]) {
        presetName = AVAssetExportPresetHighestQuality;
    } else if ([compatiblePresets containsObject:AVAssetExportPresetMediumQuality]) {
        presetName = AVAssetExportPresetMediumQuality;
    } else {
        presetName = AVAssetExportPresetLowQuality;
    }
    
    AVAssetExportSession *exportSession = [[AVAssetExportSession alloc] initWithAsset:avAsset presetName:presetName];
    exportSession.outputFileType = stringOutputFileType;
    exportSession.outputURL = outputURL;
    exportSession.shouldOptimizeForNetworkUse = optimizeForNetworkUse;

    // Configure video composition for resizing
    AVMutableVideoComposition *videoComposition = nil;
    if (newWidth != videoWidth || newHeight != videoHeight) {
        AVMutableVideoCompositionLayerInstruction *layerInstruction = [AVMutableVideoCompositionLayerInstruction videoCompositionLayerInstructionWithAssetTrack:track];

        // Calculate the scale factor
        float scaleFactorWidth = newWidth / videoWidth;
        float scaleFactorHeight = newHeight / videoHeight;

        CGAffineTransform scaleTransform = CGAffineTransformMakeScale(scaleFactorWidth, scaleFactorHeight);
        CGAffineTransform finalTransform = CGAffineTransformConcat(track.preferredTransform, scaleTransform);

        [layerInstruction setTransform:finalTransform atTime:kCMTimeZero];

        AVMutableVideoCompositionInstruction *instruction = [AVMutableVideoCompositionInstruction videoCompositionInstruction];
        instruction.timeRange = CMTimeRangeMake(kCMTimeZero, avAsset.duration);
        instruction.layerInstructions = @[layerInstruction];

        videoComposition = [AVMutableVideoComposition videoComposition];
        videoComposition.instructions = @[instruction];
        videoComposition.frameDuration = CMTimeMake(1, 30); // Adjust as necessary
        videoComposition.renderSize = CGSizeMake(newWidth, newHeight);

        exportSession.videoComposition = videoComposition;
    }

    // Set up a semaphore for the completion handler and progress timer
    dispatch_semaphore_t sessionWaitSemaphore = dispatch_semaphore_create(0);

    void (^completionHandler)(void) = ^(void)
    {
        dispatch_semaphore_signal(sessionWaitSemaphore);
    };

    // Export the video
    [self.commandDelegate runInBackground:^{
        [exportSession exportAsynchronouslyWithCompletionHandler:completionHandler];

        do {
            dispatch_time_t dispatchTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC));
            double progress = exportSession.progress * 100;

            NSMutableDictionary *dictionary = [[NSMutableDictionary alloc] init];
            [dictionary setValue: [NSNumber numberWithDouble: progress] forKey: @"progress"];

            CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary: dictionary];

            [result setKeepCallbackAsBool:YES];
            [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
            dispatch_semaphore_wait(sessionWaitSemaphore, dispatchTime);
        } while( exportSession.status < AVAssetExportSessionStatusCompleted );

        // Handle completion
        if (exportSession.status == AVAssetExportSessionStatusCompleted)
        {
            NSLog(@"Video export succeeded");
            if (saveToPhotoAlbum) {
                UISaveVideoAtPathToSavedPhotosAlbum(outputPath, self, nil, nil);
            }
            if(deleteInputFile) {
                NSString *videoThumbnailPath = [self getVideoLargeThumbnail:inputFilePath];
                [self deleteVideoFileAtPath: inputFilePath];
                [self deleteVideoFileAtPath: videoThumbnailPath];
            }
            [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:outputPath] callbackId:command.callbackId];
        }
        else if (exportSession.status == AVAssetExportSessionStatusCancelled)
        {
            NSLog(@"Video export cancelled");
            [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Video export cancelled"] callbackId:command.callbackId];
        }
        else
        {
            NSString *error = [NSString stringWithFormat:@"Video export failed with error: %@ (%ld)", exportSession.error.localizedDescription, (long)exportSession.error.code];
            [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:error] callbackId:command.callbackId];
        }
    }];
}

- (void)deleteVideoFileAtPath:(NSString *)filePath {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    NSError *error = nil;
    if ([fileManager fileExistsAtPath:filePath]) {
        BOOL success = [fileManager removeItemAtPath:filePath error:&error];
        if (success) {
            NSLog(@"File deleted successfully.");
        } else {
            NSLog(@"Could not delete file. Error: %@", error.localizedDescription);
        }
    } else {
        NSLog(@"File does not exist at path: %@", filePath);
    }
}

- (NSString *)getVideoLargeThumbnail:(NSString *)filePath {
    NSUInteger stringLength = [filePath length];
    NSString *videoThumbnailWithoutExtension = [filePath substringToIndex: stringLength - 3];
    NSString *videoThumbnail = [NSString stringWithFormat:@"%@%@", videoThumbnailWithoutExtension, @"largeThumbnail"];
    return videoThumbnail;
}

/**
 * createThumbnail
 *
 * Creates a thumbnail from the start of a video.
 *
 * ARGUMENTS
 * =========
 * fileUri        - input file path
 * outputFileName - output file name
 * atTime         - location in the video to create the thumbnail (in seconds),
 * width          - width of the thumbnail (optional)
 * height         - height of the thumbnail (optional)
 * quality        - quality of the thumbnail (between 1 and 100)
 *
 * RESPONSE
 * ========
 *
 * outputFilePath - path to output file
 *
 * @param CDVInvokedUrlCommand command
 * @return void
 */
- (void) createThumbnail:(CDVInvokedUrlCommand*)command
{
    NSLog(@"createThumbnail");
    NSDictionary* options = [command.arguments objectAtIndex:0];

    if ([options isKindOfClass:[NSNull class]]) {
        options = [NSDictionary dictionary];
    }

    NSString* srcVideoPath = [options objectForKey:@"fileUri"];
    NSString* outputFileName = [options objectForKey:@"outputFileName"];
    float atTime = ([options objectForKey:@"atTime"]) ? [[options objectForKey:@"atTime"] floatValue] : 0;
    float width = [[options objectForKey:@"width"] floatValue];
    float height = [[options objectForKey:@"height"] floatValue];
    float quality = ([options objectForKey:@"quality"]) ? [[options objectForKey:@"quality"] floatValue] : 100;
    float thumbQuality = quality * 1.0 / 100;

    int32_t preferredTimeScale = 600;
    CMTime time = CMTimeMakeWithSeconds(atTime, preferredTimeScale);

    UIImage* thumbnail = [self generateThumbnailImage:srcVideoPath atTime:time];

    if (width && height) {
        NSLog(@"got width and height, resizing image");
        CGSize newSize = CGSizeMake(width, height);
        thumbnail = [self scaleImage:thumbnail toSize:newSize];
        NSLog(@"new size of thumbnail, width x height = %f x %f", thumbnail.size.width, thumbnail.size.height);
    }

    NSString *cacheDir = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) objectAtIndex:0];
    NSString *outputFilePath = [cacheDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.%@", outputFileName, @"jpg"]];

    // write out the thumbnail
    if ([UIImageJPEGRepresentation(thumbnail, thumbQuality) writeToFile:outputFilePath atomically:YES])
    {
        NSLog(@"path to your video thumbnail: %@", outputFilePath);
        [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:outputFilePath] callbackId:command.callbackId];
    }
    else
    {
        [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"failed to create thumbnail file"] callbackId:command.callbackId];
    }
}

/**
 * getVideoInfo
 *
 * Creates a thumbnail from the start of a video.
 *
 * ARGUMENTS
 * =========
 * fileUri       - input file path
 *
 * RESPONSE
 * ========
 *
 * width              - width of the video
 * height             - height of the video
 * orientation        - orientation of the video
 * duration           - duration of the video (in seconds)
 * size               - size of the video (in bytes)
 * bitrate            - bitrate of the video (in bits per second)
 * videoMediaType     - Media type of the video
 * audioMediaType     - Media type of the audio track in video
 *
 * @param CDVInvokedUrlCommand command
 * @return void
 */
- (void) getVideoInfo:(CDVInvokedUrlCommand*)command
{
    NSLog(@"getVideoInfo");
    NSDictionary* options = [command.arguments objectAtIndex:0];

    if ([options isKindOfClass:[NSNull class]]) {
        options = [NSDictionary dictionary];
    }

    NSString *filePath = [options objectForKey:@"fileUri"];
    NSURL *fileURL = [self getURLFromFilePath:filePath];

    unsigned long long size = [[NSFileManager defaultManager] attributesOfItemAtPath:[fileURL path] error:nil].fileSize;

    AVURLAsset *avAsset = [AVURLAsset URLAssetWithURL:fileURL options:nil];

    NSArray *videoTracks = [avAsset tracksWithMediaType:AVMediaTypeVideo];
    NSArray *audioTracks = [avAsset tracksWithMediaType:AVMediaTypeAudio];
    AVAssetTrack *videoTrack = [videoTracks objectAtIndex:0];
    AVAssetTrack *audioTrack = nil;
    if (audioTracks.count > 0) {
        audioTrack = [audioTracks objectAtIndex:0];
    }

    NSString *videoMediaType = nil;
    NSString *audioMediaType = nil;
    if (videoTrack.formatDescriptions.count > 0) {
        videoMediaType = getMediaTypeFromDescription(videoTrack.formatDescriptions[0]);
    }
    if (audioTrack != nil && audioTrack.formatDescriptions.count > 0) {
        audioMediaType = getMediaTypeFromDescription(audioTrack.formatDescriptions[0]);
    }

    CGSize mediaSize = videoTrack.naturalSize;
    float videoWidth = mediaSize.width;
    float videoHeight = mediaSize.height;
    float aspectRatio = videoWidth / videoHeight;

    // for some portrait videos ios gives the wrong width and height, this fixes that
    NSString *videoOrientation = [self getOrientationForTrack:avAsset];
    if ([videoOrientation isEqual: @"portrait"]) {
        if (videoWidth > videoHeight) {
            videoWidth = mediaSize.height;
            videoHeight = mediaSize.width;
            aspectRatio = videoWidth / videoHeight;
        }
    }

    NSMutableDictionary *dict = [[NSMutableDictionary alloc] init];
    [dict setObject:[NSNumber numberWithFloat:videoWidth] forKey:@"width"];
    [dict setObject:[NSNumber numberWithFloat:videoHeight] forKey:@"height"];
    [dict setValue:videoOrientation forKey:@"orientation"];
    [dict setValue:[NSNumber numberWithFloat:videoTrack.timeRange.duration.value / 600.0] forKey:@"duration"];
    [dict setObject:[NSNumber numberWithLongLong:size] forKey:@"size"];
    [dict setObject:[NSNumber numberWithFloat:videoTrack.estimatedDataRate] forKey:@"bitrate"];
    [dict setValue:videoMediaType forKey:@"videoMediaType"];
    [dict setValue:audioMediaType forKey:@"audioMediaType"];

    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:dict] callbackId:command.callbackId];
}

/**
 * trim
 *
 * Performs a trim operation on a clip, while encoding it.
 *
 * ARGUMENTS
 * =========
 * fileUri        - input file path
 * trimStart      - time to start trimming
 * trimEnd        - time to end trimming
 * outputFileName - output file name
 * progress:      - optional callback function that receives progress info
 *
 * RESPONSE
 * ========
 *
 * outputFilePath - path to output file
 *
 * @param CDVInvokedUrlCommand command
 * @return void
 */
- (void) trim:(CDVInvokedUrlCommand*)command {
    NSLog(@"[Trim]: trim called");

    // extract arguments
    NSDictionary* options = [command.arguments objectAtIndex:0];
    if ([options isKindOfClass:[NSNull class]]) {
        options = [NSDictionary dictionary];
    }
    NSString *inputFilePath = [options objectForKey:@"fileUri"];
    NSURL *inputFileURL = [self getURLFromFilePath:inputFilePath];
    float trimStart = [[options objectForKey:@"trimStart"] floatValue];
    float trimEnd = [[options objectForKey:@"trimEnd"] floatValue];
    NSString *outputName = [options objectForKey:@"outputFileName"];

    NSFileManager *fileMgr = [NSFileManager defaultManager];
    NSString *cacheDir = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) objectAtIndex:0];

    // videoDir
    NSString *videoDir = [cacheDir stringByAppendingPathComponent:@"mp4"];
    if ([fileMgr createDirectoryAtPath:videoDir withIntermediateDirectories:YES attributes:nil error: NULL] == NO){
        [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"failed to create video dir"] callbackId:command.callbackId];
        return;
    }
    NSString *videoOutput = [videoDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.%@", outputName, @"mp4"]];

    NSLog(@"[Trim]: inputFilePath: %@", inputFilePath);
    NSLog(@"[Trim]: outputPath: %@", videoOutput);

    // run in background
    [self.commandDelegate runInBackground:^{

        AVURLAsset *avAsset = [AVURLAsset URLAssetWithURL:inputFileURL options:nil];

        AVAssetExportSession *exportSession = [[AVAssetExportSession alloc]initWithAsset:avAsset presetName: AVAssetExportPresetHighestQuality];
        exportSession.outputURL = [NSURL fileURLWithPath:videoOutput];
        exportSession.outputFileType = AVFileTypeQuickTimeMovie;
        exportSession.shouldOptimizeForNetworkUse = YES;

        int32_t preferredTimeScale = 600;
        CMTime startTime = CMTimeMakeWithSeconds(trimStart, preferredTimeScale);
        CMTime stopTime = CMTimeMakeWithSeconds(trimEnd, preferredTimeScale);
        CMTimeRange exportTimeRange = CMTimeRangeFromTimeToTime(startTime, stopTime);
        exportSession.timeRange = exportTimeRange;

        // debug timings
        NSString *trimStart = (NSString *) CFBridgingRelease(CMTimeCopyDescription(NULL, startTime));
        NSString *trimEnd = (NSString *) CFBridgingRelease(CMTimeCopyDescription(NULL, stopTime));
        NSLog(@"[Trim]: duration: %lld, trimStart: %@, trimEnd: %@", avAsset.duration.value, trimStart, trimEnd);

        //  Set up a semaphore for the completion handler and progress timer
        dispatch_semaphore_t sessionWaitSemaphore = dispatch_semaphore_create(0);

        void (^completionHandler)(void) = ^(void)
        {
            dispatch_semaphore_signal(sessionWaitSemaphore);
        };

        // do it
        [exportSession exportAsynchronouslyWithCompletionHandler:completionHandler];

        do {
            dispatch_time_t dispatchTime = DISPATCH_TIME_FOREVER;  // if we dont want progress, we will wait until it finishes.
            dispatchTime = getDispatchTimeFromSeconds((float)1.0);
            double progress = [exportSession progress] * 100;

            NSLog([NSString stringWithFormat:@"AVAssetExport running progress=%3.2f%%", progress]);

            NSMutableDictionary *dictionary = [[NSMutableDictionary alloc] init];
            [dictionary setValue: [NSNumber numberWithDouble: progress] forKey: @"progress"];

            CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary: dictionary];

            [result setKeepCallbackAsBool:YES];
            [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
            dispatch_semaphore_wait(sessionWaitSemaphore, dispatchTime);
        } while( [exportSession status] < AVAssetExportSessionStatusCompleted );

        // this is kinda odd but must be done
        if ([exportSession status] == AVAssetExportSessionStatusCompleted) {
            NSMutableDictionary *dictionary = [[NSMutableDictionary alloc] init];
            // AVAssetExportSessionStatusCompleted will not always mean progress is 100 so hard code it below
            double progress = 100.00;
            [dictionary setValue: [NSNumber numberWithDouble: progress] forKey: @"progress"];

            CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary: dictionary];

            [result setKeepCallbackAsBool:YES];
            [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
        }

        switch ([exportSession status]) {
            case AVAssetExportSessionStatusCompleted:
                NSLog(@"[Trim]: Export Complete %d %@", exportSession.status, exportSession.error);
                [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:videoOutput] callbackId:command.callbackId];
                break;
            case AVAssetExportSessionStatusFailed:
                NSLog(@"[Trim]: Export failed: %@", [[exportSession error] localizedDescription]);
                [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:[[exportSession error] localizedDescription]] callbackId:command.callbackId];
                break;
            case AVAssetExportSessionStatusCancelled:
                NSLog(@"[Trim]: Export canceled");
                break;
            default:
                NSLog(@"[Trim]: Export default in switch");
                break;
        }

    }];
}

// modified version of http://stackoverflow.com/a/21230645/1673842
- (UIImage *)generateThumbnailImage: (NSString *)srcVideoPath atTime:(CMTime)time
{
    NSURL *url = [NSURL fileURLWithPath:srcVideoPath];

    if ([srcVideoPath rangeOfString:@"://"].location == NSNotFound)
    {
        url = [NSURL URLWithString:[[@"file://localhost" stringByAppendingString:srcVideoPath] stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];
    }
    else
    {
        url = [NSURL URLWithString:[srcVideoPath stringByAddingPercentEscapesUsingEncoding: NSUTF8StringEncoding]];
    }

    AVAsset *asset = [AVAsset assetWithURL:url];
    AVAssetImageGenerator *imageGenerator = [[AVAssetImageGenerator alloc] initWithAsset:asset];
    imageGenerator.requestedTimeToleranceAfter = kCMTimeZero; // needed to get a precise time (http://stackoverflow.com/questions/5825990/i-cannot-get-a-precise-cmtime-for-generating-still-image-from-1-8-second-video)
    imageGenerator.requestedTimeToleranceBefore = kCMTimeZero; // ^^
    imageGenerator.appliesPreferredTrackTransform = YES; // crucial to have the right orientation for the image (http://stackoverflow.com/questions/9145968/getting-video-snapshot-for-thumbnail)
    CGImageRef imageRef = [imageGenerator copyCGImageAtTime:time actualTime:NULL error:NULL];
    UIImage *thumbnail = [UIImage imageWithCGImage:imageRef];
    CGImageRelease(imageRef);  // CGImageRef won't be released by ARC

    return thumbnail;
}

// to scale images without changing aspect ratio (http://stackoverflow.com/a/8224161/1673842)
- (UIImage*)scaleImage:(UIImage*)image
                toSize:(CGSize)newSize;
{
    float oldWidth = image.size.width;
    float scaleFactor = newSize.width / oldWidth;

    float newHeight = image.size.height * scaleFactor;
    float newWidth = oldWidth * scaleFactor;

    UIGraphicsBeginImageContext(CGSizeMake(newWidth, newHeight));
    [image drawInRect:CGRectMake(0, 0, newWidth, newHeight)];
    UIImage *newImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return newImage;
}

// inspired by http://stackoverflow.com/a/6046421/1673842
- (NSString*)getOrientationForTrack:(AVAsset *)asset
{
    AVAssetTrack *videoTrack = [[asset tracksWithMediaType:AVMediaTypeVideo] objectAtIndex:0];
    CGSize size = [videoTrack naturalSize];
    CGAffineTransform txf = [videoTrack preferredTransform];

    if (size.width == txf.tx && size.height == txf.ty)
        return @"landscape";
    else if (txf.tx == 0 && txf.ty == 0)
        return @"landscape";
    else if (txf.tx == 0 && txf.ty == size.width)
        return @"portrait";
    else
        return @"portrait";
}

- (NSURL*)getURLFromFilePath:(NSString*)filePath
{
    if ([filePath containsString:@"assets-library://"]) {
        return [NSURL URLWithString:[filePath stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];
    } else if ([filePath containsString:@"file://"]) {
        return [NSURL URLWithString:[filePath stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];
    }

    return [NSURL fileURLWithPath:[filePath stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];
}

static NSString* getMediaTypeFromDescription(id description) {
    CMFormatDescriptionRef desc = (__bridge CMFormatDescriptionRef)description;
    FourCharCode code = CMFormatDescriptionGetMediaSubType(desc);

    NSString *result = [NSString stringWithFormat:@"%c%c%c%c",
                        (code >> 24) & 0xff,
                        (code >> 16) & 0xff,
                        (code >> 8) & 0xff,
                        code & 0xff];
    NSCharacterSet *characterSet = [NSCharacterSet whitespaceCharacterSet];
    return [result stringByTrimmingCharactersInSet:characterSet];
}

static dispatch_time_t getDispatchTimeFromSeconds(float seconds) {
    long long milliseconds = seconds * 1000.0;
    dispatch_time_t waitTime = dispatch_time( DISPATCH_TIME_NOW, 1000000LL * milliseconds );
    return waitTime;
}

@end
