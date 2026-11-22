#pragma once
#include <cstdlib>
#include <QString>
namespace KisDomUtils {
// This driver only constructs curves from typed points.
inline double toDouble(const QString &, bool *) { std::abort(); }
}
