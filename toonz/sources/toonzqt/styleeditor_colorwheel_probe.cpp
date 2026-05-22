#include "toonzqt/styleeditor.h"

#include <QApplication>
#include <QColor>
#include <QImage>
#include <QPainter>

#include <cstdlib>
#include <iostream>

namespace {

bool fail(const char *message) {
  std::cerr << "styleeditor_colorwheel_probe: " << message << std::endl;
  return false;
}

bool hasMeaningfulColorWheelPixels(const QImage &image,
                                   const QColor &background) {
  int nonBackgroundPixels = 0;
  int saturatedPixels     = 0;

  for (int y = 0; y != image.height(); ++y) {
    const QRgb *scanLine =
        reinterpret_cast<const QRgb *>(image.constScanLine(y));
    for (int x = 0; x != image.width(); ++x) {
      const QColor color = QColor::fromRgba(scanLine[x]);
      if (color.alpha() == 0) continue;
      if (qAbs(color.red() - background.red()) > 4 ||
          qAbs(color.green() - background.green()) > 4 ||
          qAbs(color.blue() - background.blue()) > 4) {
        ++nonBackgroundPixels;
      }
      if (color.saturation() > 80 && color.value() > 80) ++saturatedPixels;
    }
  }

  return nonBackgroundPixels > image.width() * image.height() / 10 &&
         saturatedPixels > 64;
}

}  // namespace

int main(int argc, char *argv[]) {
  QApplication app(argc, argv);

  StyleEditorGUI::HexagonalColorWheel wheel(nullptr);
  wheel.resize(180, 140);
  wheel.setBGColor(QColor(128, 128, 128));

  StyleEditorGUI::ColorModel color;
  color.setValue(StyleEditorGUI::eHue, 210);
  color.setValue(StyleEditorGUI::eSaturation, 72);
  color.setValue(StyleEditorGUI::eValue, 85);
  wheel.setColor(color);

  QImage image(wheel.size(), QImage::Format_ARGB32_Premultiplied);
  image.fill(Qt::transparent);

  QPainter painter(&image);
  wheel.render(&painter);
  painter.end();

  if (image.isNull()) {
    fail("rendered image is null");
    return EXIT_FAILURE;
  }
  if (!hasMeaningfulColorWheelPixels(image, wheel.getBGColor())) {
    fail("rendered color wheel does not contain expected color pixels");
    return EXIT_FAILURE;
  }

  std::cout << "styleeditor_colorwheel_probe: ok" << std::endl;
  return EXIT_SUCCESS;
}
