// SPDX-License-Identifier: GPL-2.0-or-later
#include "kis_cubic_curve.h"
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <cmath>
#include <iostream>
#include <iterator>
#include <string>

namespace {
constexpr int resolution = 1024;
constexpr int maxPoints = 32;
constexpr int maxSamples = 4096;

int invalid()
{
    std::cout << "{\"error\":{\"type\":\"InvalidRequest\"}}\n";
    return 3;
}

bool inUnitInterval(const QJsonValue &value)
{
    return value.isDouble() && value.toDouble() >= 0 && value.toDouble() <= 1;
}
}

int main()
{
    const std::string input{std::istreambuf_iterator<char>(std::cin), {}};
    const auto document = QJsonDocument::fromJson(QByteArray::fromStdString(input));
    const auto request = document.object();
    const auto pointList = request.value("points");
    const auto samples = request.value("samples");
    if (!pointList.isArray() || !samples.isArray()) return invalid();
    const auto points = pointList.toArray();
    const auto pressures = samples.toArray();
    if (points.isEmpty() || points.size() > maxPoints || pressures.size() > maxSamples)
        return invalid();

    QList<KisCubicCurvePoint> knots;
    for (const auto &value : points) {
        const auto point = value.toObject();
        const auto x = point.value("x");
        const auto y = point.value("y");
        const auto corner = point.value("corner");
        if (!inUnitInterval(x) || !inUnitInterval(y) || (!corner.isUndefined() && !corner.isBool()))
            return invalid();
        if (!knots.isEmpty() && x.toDouble() - knots.last().x() < 1.0 / resolution)
            return invalid();
        knots.append({x.toDouble(), y.toDouble(), corner.toBool()});
    }
    for (const auto &sample : pressures)
        if (!sample.isDouble() || !std::isfinite(sample.toDouble())) return invalid();

    const auto transfer = KisCubicCurve(knots).floatTransfer(resolution + 1);
    QJsonArray result;
    for (const auto &sample : pressures) {
        const auto mapped = KisCubicCurve::interpolateLinear(sample.toDouble(), transfer);
        result.append(static_cast<int>(std::llround(mapped * 1e9)));
    }
    std::cout << QJsonDocument(result).toJson(QJsonDocument::Compact).constData() << '\n';
}
