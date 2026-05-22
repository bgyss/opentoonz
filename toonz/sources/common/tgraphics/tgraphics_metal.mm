#include "tgraphics.h"

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>

#include <algorithm>
#include <string>

namespace TGraphics {
namespace {

struct MetalState {
  id<MTLDevice> m_device = nil;
  id<MTLCommandQueue> m_commandQueue = nil;
  std::string m_deviceName;

  MetalState() {
    m_device = MTLCreateSystemDefaultDevice();
    if (!m_device) return;

    m_commandQueue       = [m_device newCommandQueue];
    const char *nameUtf8 = [[m_device name] UTF8String];
    m_deviceName         = nameUtf8 ? nameUtf8 : "";
  }

  ~MetalState() {
#if !__has_feature(objc_arc)
    [m_commandQueue release];
    [m_device release];
#endif
  }
};

MetalState &metalState() {
  static MetalState state;
  return state;
}

class MetalLayerRenderTarget final : public RenderTarget {
  CAMetalLayer *m_layer = nil;
  int m_width           = 0;
  int m_height          = 0;
  double m_scale        = 1.0;

public:
  MetalLayerRenderTarget(CAMetalLayer *layer, int width, int height,
                         double devicePixelRatio)
      : m_layer(layer)
      , m_width(std::max(1, width))
      , m_height(std::max(1, height))
      , m_scale(devicePixelRatio > 0.0 ? devicePixelRatio : 1.0) {
#if !__has_feature(objc_arc)
    [m_layer retain];
#endif

    MetalState &state       = metalState();
    m_layer.device          = state.m_device;
    m_layer.pixelFormat     = MTLPixelFormatBGRA8Unorm;
    m_layer.framebufferOnly = YES;
    m_layer.drawableSize    = CGSizeMake(m_width * m_scale, m_height * m_scale);
  }

  ~MetalLayerRenderTarget() override {
#if !__has_feature(objc_arc)
    [m_layer release];
#endif
  }
};

}  // namespace

bool probeMetalDevice() {
  MetalState &state = metalState();
  return state.m_device && state.m_commandQueue;
}

const char *probeMetalDeviceName() {
  MetalState &state = metalState();
  return probeMetalDevice() ? state.m_deviceName.c_str() : "";
}

std::unique_ptr<RenderTarget> createNativeMetalLayerRenderTarget(
    void *metalLayer, int width, int height, double devicePixelRatio) {
  if (!probeMetalDevice() || !metalLayer) return std::unique_ptr<RenderTarget>();

  CAMetalLayer *layer = static_cast<CAMetalLayer *>(metalLayer);
  if (![layer isKindOfClass:[CAMetalLayer class]]) {
    return std::unique_ptr<RenderTarget>();
  }

  return std::unique_ptr<RenderTarget>(
      new MetalLayerRenderTarget(layer, width, height, devicePixelRatio));
}

bool isNativeMetalLayerRenderTarget(const RenderTarget *target) {
  return dynamic_cast<const MetalLayerRenderTarget *>(target) != nullptr;
}

}  // namespace TGraphics
