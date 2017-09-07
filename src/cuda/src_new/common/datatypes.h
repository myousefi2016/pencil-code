/*
* Definitions for the datatypes used throughout the program
* 
*/
#pragma once
#include <float.h> // For DBL_MAX and FLT_MAX

#define USE_DOUBLE_PRECISION 0
#if USE_DOUBLE_PRECISION == 1
    typedef double real;
    const double REAL_MAX = DBL_MAX;
    const double REAL_MIN = DBL_MIN;
    const double REAL_EPSILON = DBL_EPSILON;
    #define REAL_FORMAT_SPECIFIER "%lf"
#else
    typedef float real;
    const float REAL_MAX = FLT_MAX;
    const double REAL_MIN = FLT_MIN;
    const double REAL_EPSILON = FLT_EPSILON;
    #define REAL_FORMAT_SPECIFIER "%f"
#endif

//Vector of 3 real type values (float or double depending on the definition of "real")
typedef struct vec3r {
    real x, y, z;
} vec3r;

//Vector of 3 integers
typedef struct vec3i {
    int x, y, z;
} vec3i;


typedef enum {MAX_VEC, MIN_VEC, RMS_VEC, MAX_SCAL, MIN_SCAL, RMS_SCAL, RMS_EXP, NUM_REDUCT_TYPES} ReductType;

typedef enum {LNRHO, UU_X, UU_Y, UU_Z, UU, NUM_ARR_TYPES} ArrType;



