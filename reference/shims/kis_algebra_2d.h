#pragma once
#include <QtGlobal>
namespace KisAlgebra2D {
template <class T> T copysign(T magnitude, T sign)
{
    return sign >= T(0) ? qAbs(magnitude) : -qAbs(magnitude);
}
}
