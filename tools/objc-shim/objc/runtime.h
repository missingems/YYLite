#pragma once
#include <stddef.h>
#include <stdint.h>
typedef struct objc_class *Class;
typedef struct objc_object { Class isa; } *id;
typedef struct objc_selector *SEL;
typedef struct objc_property *objc_property_t;
typedef signed char BOOL;
#ifndef YES
#define YES ((BOOL)1)
#define NO  ((BOOL)0)
#endif
Class objc_getClass(const char *name);
Class class_getSuperclass(Class cls);
objc_property_t *class_copyPropertyList(Class cls, unsigned int *outCount);
const char *property_getName(objc_property_t property);
const char *property_getAttributes(objc_property_t property);
