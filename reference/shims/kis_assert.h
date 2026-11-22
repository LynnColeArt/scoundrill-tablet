#pragma once
#include <cstdlib>
#define KIS_SAFE_ASSERT_RECOVER(condition) if (!(condition))
#define KIS_SAFE_ASSERT_RECOVER_RETURN(condition) if (!(condition)) std::abort()
#define KIS_SAFE_ASSERT_RECOVER_RETURN_VALUE(condition, value) if (!(condition)) std::abort()
