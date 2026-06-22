// EngineBridge.h — Obj-C facade over magentart::core::RealtimeRunner.
// Pure Obj-C in the public interface so Swift can import it via the
// bridging header. All C++ types are hidden in EngineBridge.mm.

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, XFPromptStatus) {
    XFPromptStatusIdle   = 0,
    XFPromptStatusFetching = 1,
    XFPromptStatusSuccess  = 2,
    XFPromptStatusError    = 3,
};

typedef NS_ENUM(NSInteger, XFOnsetMode) {
    XFOnsetModeMasked  = 0, // Auto-Strum ON: model places onsets.
    XFOnsetModeUnmasked = 1, // Auto-Strum OFF: user controls attack timing.
};

typedef NS_ENUM(NSInteger, XFResetKind) {
    XFResetKindNone      = 0,
    XFResetKindUser      = 1,
    XFResetKindTransport = 2,
};

typedef struct {
    float transformerMs;
    float totalMs;
    NSUInteger bufferAvailable;
    NSUInteger bufferCapacity;
    int transportFlags;
    uint64_t droppedFrames;
} XFEngineMetrics;

// Block called by prefill / state operations with log lines.
typedef void (^XFLogCallback)(NSString *line);

@interface EngineBridge : NSObject

// MARK: - Lifecycle (main thread only)

- (BOOL)initAssets:(NSString *)resourceDir;
- (BOOL)loadModel:(NSString *)mlxfnPath;
- (BOOL)loadPrefillModel:(NSString *)spectrostreamPath
              prefillPath:(nullable NSString *)prefillPath;
- (BOOL)isLoaded;

- (void)start;
- (void)stop;
- (void)unload;

// MARK: - Audio output (audio thread)

// Pull `count` stereo samples into destL / destR. Returns NO on underrun
// (dest is still filled with `count` samples, zero-padded). Never block
// from the realtime audio callback.
- (BOOL)readAudioStereoL:(float *)destL
                      R:(float *)destR
                  count:(NSUInteger)count;

// Offline render variant — may block waiting for samples.
- (BOOL)readAudioStereoBlockingL:(float *)destL
                              R:(float *)destR
                          count:(NSUInteger)count;

// MARK: - Prompts

- (void)setTextPrompt:(NSString *)text;
- (void)setTextPrompts:(NSArray<NSString *> *)texts weights:(NSArray<NSNumber *> *)weights;

// Queue audio PCM for prompt slot `index` (0..5). Encoding happens on the
// MusicCoCa worker thread; poll -promptStatus: for completion.
- (void)setAudioPromptSamplesForIndex:(int)index
                              filename:(NSString *)filename
                               samples:(const float *)samples
                                 count:(NSUInteger)count
              NS_SWIFT_NAME(setAudioPromptSamplesForIndex(_:filename:samples:count:));

// Directly set the 768-dim embedding for slot `index`.
- (void)setAudioEmbeddingForIndex:(int)index embedding:(const float *)embedding
              NS_SWIFT_NAME(setAudioEmbeddingForIndex(_:embedding:));

// Read back the 768-dim embedding currently in slot `index` into `out`
// (must point to 768 floats). Returns NO if slot is empty.
- (BOOL)getAudioEmbeddingForIndex:(int)index out:(float *)out
              NS_SWIFT_NAME(getAudioEmbeddingForIndex(_:out:));

- (XFPromptStatus)textEncoderStatus;
- (XFPromptStatus)promptStatusForIndex:(int)index NS_SWIFT_NAME(promptStatusForIndex(_:));
- (XFPromptStatus)quantizerStatus;
- (nullable NSString *)cachedTextForIndex:(int)index;
- (int)activePromptCount;
- (int)rvqDepth;

// MARK: - Blend weights (per-slot, 0..1, should sum to 1)

- (void)setBlendWeightForIndex:(int)index weight:(float)weight
              NS_SWIFT_NAME(setBlendWeightForIndex(_:weight:));
- (float)blendWeightForIndex:(int)index NS_SWIFT_NAME(blendWeightForIndex(_:));
- (void)setBlendWeights:(const float *)weights count:(int)count;

// Re-blend cached embeddings with new weights. Optional PCA coefficients
// are applied to slots whose cached text is "pca".
- (BOOL)reblendMusiccocaTokensWithWeights:(const float *)weights
                                    count:(int)count
                              pcaCoeffs:(nullable const float *)pcaCoeffs
                              pcaCount:(int)pcaCount;

// MARK: - PCA corpus

- (BOOL)loadPcaFile:(NSString *)path;
- (BOOL)isPcaLoaded;
- (int)pcaComponentCount;
- (int)pcaCentroidCount;
- (void)setPcaCoeffForIndex:(int)index value:(float)value
              NS_SWIFT_NAME(setPcaCoeffForIndex(_:value:));
- (float)pcaCoeffForIndex:(int)index NS_SWIFT_NAME(pcaCoeffForIndex(_:));

// MARK: - Sampling parameters (atomic, any thread)

- (void)setTemperature:(float)t;
- (float)temperature;
- (void)setTopK:(int)k;
- (int)topK;
- (void)setCfgMusiccoca:(float)v;
- (float)cfgMusiccoca;
- (void)setCfgNotes:(float)v;
- (float)cfgNotes;
- (void)setCfgDrums:(float)v;
- (float)cfgDrums;
- (void)setUnmaskWidth:(int)w;
- (int)unmaskWidth;
- (void)setSeedRotation:(int)r;
- (int)seedRotation;

// MARK: - MIDI notes (atomic, any thread)

- (void)setNoteOn:(int)n;
- (void)setNoteOff:(int)n;
- (void)setOnsetMode:(XFOnsetMode)mode;
- (XFOnsetMode)onsetMode;
- (void)setDrumless:(BOOL)on;
- (BOOL)drumless;
- (void)setMidiGateEnabled:(BOOL)enabled;
- (BOOL)midiGateEnabled;

// MARK: - Output control

- (void)setVolumeDb:(float)v;
- (float)volumeDb;
- (void)setMute:(BOOL)m;
- (BOOL)mute;
- (void)setLatencyComp:(BOOL)c;
- (BOOL)latencyComp;
- (void)setBypass:(BOOL)b;
- (BOOL)bypass;
- (void)setBufferSize:(NSUInteger)cap;
- (NSUInteger)bufferSize;
- (NSUInteger)latencySamples;

// MARK: - Reset & prefill

- (void)triggerReset;
- (void)triggerTransportReset;
- (void)resetForPlayback;
- (void)reset;

// Prefill from audio PCM. `samples` is interleaved stereo at 48 kHz.
// RealtimeRunner trims ~1s from each end automatically (SpectroStream
// encoder edges are unreliable). Checkpoints so -reset returns here.
- (BOOL)prefillStateWithSamples:(const float *)samples
                    sampleCount:(int)sampleCount
                    logCallback:(nullable XFLogCallback)logCallback;

- (BOOL)prefillSilenceWithDurationFrames:(int)durationFrames
                           logCallback:(nullable XFLogCallback)logCallback;

// MARK: - State persistence

- (BOOL)saveStateToPath:(NSString *)path;
- (BOOL)loadStateFromPath:(NSString *)path;
- (void)resetToFactory;

// MARK: - Recording

- (void)startRecording;
- (void)stopRecording;
- (void)clearRecording;
- (NSUInteger)recordedSampleCount;
- (BOOL)getRecordedAudioL:(float *)destL R:(float *)destR
                startIdx:(NSUInteger)startIdx
                  count:(NSUInteger)count;
- (NSArray<NSNumber *> *)waveformPeaksForBuckets:(int)numBuckets;

// MARK: - Metrics

- (XFEngineMetrics)metrics;
- (void)resetDroppedFrames;

// MARK: - Transport / offline

- (void)setTransportFlags:(int)flags;
- (void)setOffline:(BOOL)offline;

@end

NS_ASSUME_NONNULL_END
