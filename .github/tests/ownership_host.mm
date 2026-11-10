// Adapted from miyako/4d-plugin-running-application at
// 739c2c1e0bed703e27ee610854e2d90f5806db91; same seven bundled SDK blobs.
#include "4DPlugin-Shell-Execute.h"
#include "ARRAY_TEXT.h"
#include "C_BLOB.h"
#include "C_LONGINT.h"
#include "PrivateTypes.h"
#include "EntryPoints.h"
#include <cassert>
#include <cstdlib>
#include <cstring>
#include <iostream>
#include <map>
#include <set>
#include <stdexcept>
#include <type_traits>

extern Call4DProcPtr gCall4D;
extern "C" FOURDCALL FourDPackex(PA_long32, void *, void **, void *);
static bool allocatedEmpty = true, failProperty, failHas, failString, failResize;
static int failHandleCountdown, failCommand, wrongCommand, appCount = 3, operations;
static std::map<PA_Unichar *, size_t> strings;
static std::map<PA_Handle, size_t> handles;
struct Ref {
    int owners = 1;
    std::map<CUTF16String, PA_Variable> properties;
    std::vector<PA_Variable> elements;
};
static std::set<Ref *> refs;
static std::set<void *> pictures;
static int stringCreates, stringDisposes, refCreates, refDisposes;
static int handleCreates, handleDisposes, pictureCreates, pictureDisposes;

static CUTF16String u16(const char *text)
{
    NSString *s = [NSString stringWithUTF8String:text];
    CUTF16String result([s length], 0);
    if(!result.empty()) [s getCharacters:&result[0] range:NSMakeRange(0, [s length])];
    return result;
}
static CUTF8String u8(const char *text) { return CUTF8String((const uint8_t *)text); }
static PA_Unistring makeString(const CUTF16String& text)
{
    PA_Unistring result = {};
    result.fLength = (PA_long32)text.size();
    if(!text.empty() || allocatedEmpty)
    {
        result.fString = new PA_Unichar[text.size() + 1];
        std::copy(text.begin(), text.end(), result.fString);
        result.fString[text.size()] = 0;
        result.fReserved1 = (PA_long32)(text.size() + 1);
        PA_Unichar *pointer = result.fString;
        strings[pointer] = text.size() + 1;
        ++stringCreates;
    }
    return result;
}
static CUTF16String readString(PA_Unistring value)
{
    PA_Unichar *pointer = value.fString;
    if(!pointer) { assert(value.fLength == 0); return {}; }
    assert(strings.count(pointer));
    assert(strings.at(pointer) == (size_t)value.fLength + 1);
    assert(value.fReserved1 == value.fLength + 1);
    assert(value.fString[value.fLength] == 0);
    return CUTF16String(value.fString, value.fLength);
}
static void disposeString(PA_Unistring value)
{
    PA_Unichar *pointer = value.fString;
    if(pointer) { assert(strings.erase(pointer) == 1); delete[] pointer; ++stringDisposes; }
}
static Ref *newRef()
{
    Ref *result = new Ref;
    refs.insert(result);
    ++refCreates;
    return result;
}
static void clear(PA_Variable& value);
static void dropRef(void *pointer)
{
    if(!pointer) return;
    Ref *ref = (Ref *)pointer;
    assert(refs.count(ref) && ref->owners > 0);
    if(--ref->owners == 0)
    {
        for(auto& property : ref->properties) clear(property.second);
        for(auto& element : ref->elements) clear(element);
        refs.erase(ref);
        delete ref;
        ++refDisposes;
    }
}
static PA_Variable clone(PA_Variable value)
{
    if(value.fType == eVK_Unistring)
        value.uValue.fString = makeString(readString(value.uValue.fString));
    else if(value.fType == eVK_Object || value.fType == eVK_Collection)
    {
        Ref *ref = (Ref *)value.uValue.fObject;
        if(ref) { assert(refs.count(ref)); ++ref->owners; }
    }
    else if(value.fType == eVK_Picture && value.uValue.fPicture)
    {
        void *copy = new char;
        pictures.insert(copy);
        value.uValue.fPicture = copy;
        ++pictureCreates;
    }
    return value;
}
static void clear(PA_Variable& value)
{
    assert(value.fType != 0); // raw failed-command outputs are not owners
    switch(value.fType)
    {
        case eVK_Unistring: disposeString(value.uValue.fString); break;
        case eVK_Object: case eVK_Collection: dropRef(value.uValue.fObject); break;
        case eVK_Picture:
            if(value.uValue.fPicture)
            {
                void *pointer = value.uValue.fPicture;
                assert(pictures.erase(pointer) == 1);
                delete (char *)pointer;
                ++pictureDisposes;
            }
            break;
        case eVK_ArrayUnicode:
            for(int i = 0; i <= value.uValue.fArray.fNbElements; ++i)
                disposeString(((PA_Unistring *)*value.uValue.fArray.fData)[i]);
            PA_DisposeHandle(value.uValue.fArray.fData);
            break;
        case eVK_Blob: PA_DisposeHandle(value.uValue.fBlob.fHandle); break;
        default: break;
    }
    value.fType = eVK_Undefined;
}
static PA_Variable textValue(const char *text)
{
    PA_Variable result = PA_CreateVariable(eVK_Undefined);
    PA_Unistring str = makeString(u16(text));
    PA_SetStringVariable(&result, &str);
    return result;
}
static void host(short selector, EngineBlock *eb)
{
    eb->fError = eER_NoErr;
    switch(selector)
    {
        case EX_CREATE_UNISTRING:
        {
            const PA_Unichar *text = (PA_Unichar *)eb->fHandle;
            eb->fUniString1 = makeString(text ? CUTF16String(text) : CUTF16String());
            break;
        }
        case EX_DISPOSE_UNISTRING: disposeString(eb->fUniString1); break;
        case EX_SET_UNISTRING:
        {
            CUTF16String text((PA_Unichar *)eb->fHandle);
            disposeString(eb->fUniString1);
            eb->fUniString1 = makeString(text);
            break;
        }
        case EX_VARIABLE_TO_STRING:
        {
            if(failString)
            {
                memset(&eb->fUniString1, 0xa5, sizeof(PA_Unistring));
                eb->fError = (PA_ErrorCode)1;
                break;
            }
            PA_Variable *value = (PA_Variable *)eb->fHandle;
            assert(value->fType == eVK_Unistring);
            readString(value->uValue.fString);
            eb->fUniString1 = value->uValue.fString;
            break;
        }
        case EX_CLEAR_VARIABLE: clear(*(PA_Variable *)eb->fPtr1); break;
        case EX_HANDLE_MANAGER:
        {
            PA_Handle handle = eb->fParam1 == 1 ? nullptr : eb->fHandle;
            sLONG_PTR length = eb->fParam1 == 1 || eb->fParam1 == 3 ? eb->fParam2 : 0;
            switch(eb->fParam1)
            {
                case 1:
                    if(failHandleCountdown && --failHandleCountdown == 0)
                    {
                        eb->fHandle = nullptr;
                        eb->fError = (PA_ErrorCode)1;
                        break;
                    }
                    handle = new char *;
                    *handle = (char *)calloc(std::max<sLONG_PTR>(1, length), 1);
                    handles[handle] = length;
                    eb->fHandle = handle;
                    ++handleCreates;
                    break;
                case 2:
                    assert(handles.erase(handle) == 1);
                    free(*handle);
                    delete handle;
                    ++handleDisposes;
                    break;
                case 3:
                    assert(handles.count(handle));
                    if(failResize) { eb->fError = (PA_ErrorCode)1; break; }
                    *handle = (char *)realloc(*handle, std::max<sLONG_PTR>(1, length));
                    handles[handle] = length;
                    break;
                case 4: eb->fParam2 = handles.at(handle); break;
                case 5: eb->fParam3 = (sLONG_PTR)*handle; break;
                case 6: break;
                default: std::abort();
            }
            break;
        }
        case EX_GET_INFORMATION: eb->fParam2 = 0x00002000; break;
        case EX_GET_OBJ_VALUE:
        {
            if(failProperty)
            {
                memset(eb->fPtr2, 0xa5, sizeof(PA_Variable));
                eb->fError = (PA_ErrorCode)1;
                break;
            }
            Ref *ref = (Ref *)eb->fPtr1;
            assert(refs.count(ref));
            PA_Variable *out = (PA_Variable *)eb->fPtr2;
            if(eb->fShort == eVK_Collection)
            {
                if(eb->fLongint == -1) PA_SetLongintVariable(out, (PA_long32)ref->elements.size());
                else *out = clone(ref->elements.at(eb->fLongint));
            }
            else *out = clone(ref->properties.at(readString(eb->fUniString1)));
            break;
        }
        case EX_SET_OBJ_VALUE:
        {
            Ref *ref = (Ref *)eb->fPtr1;
            assert(refs.count(ref));
            PA_Variable value = clone(*(PA_Variable *)eb->fPtr2);
            if(eb->fShort == eVK_Collection)
            {
                assert(eb->fLongint == (PA_long32)ref->elements.size());
                ref->elements.push_back(value);
            }
            else
            {
                CUTF16String key = readString(eb->fUniString1);
                if(ref->properties.count(key)) clear(ref->properties.at(key));
                ref->properties[key] = value;
            }
            break;
        }
        case EX_EXECUTE_COMMAND_BY_ID:
        {
            PA_Variable *out = (PA_Variable *)eb->fPtr2;
            if(eb->fParam1 == failCommand || (eb->fParam1 == 1231 && failHas))
            {
                memset(out, 0, sizeof(*out));
                eb->fError = (PA_ErrorCode)1;
                break;
            }
            if(eb->fParam1 == wrongCommand)
            {
                *out = textValue("wrong-kind");
                if(eb->fParam1 == 1217) { clear(*out); PA_SetObjectVariable(out, newRef()); }
                break;
            }
            PA_Variable **args = (PA_Variable **)eb->fPtr1;
            if(eb->fParam1 == 1231)
            {
                Ref *ref = (Ref *)args[0]->uValue.fObject;
                PA_SetBooleanVariable(out, ref->properties.count(readString(args[1]->uValue.fString)) != 0);
            }
            else if(eb->fParam1 == 1225)
            {
                Ref *copy = newRef();
                for(auto& property : ((Ref *)args[0]->uValue.fObject)->properties)
                    copy->properties[property.first] = clone(property.second);
                PA_SetObjectVariable(out, copy);
            }
            else if(eb->fParam1 == 1217) *out = textValue("synthetic \xE6\x97\xA5 \xF0\x9F\x98\x80");
            else if(eb->fParam1 == 1471) PA_SetObjectVariable(out, newRef());
            else if(eb->fParam1 == 1472) PA_SetCollectionVariable(out, newRef());
            else std::abort();
            break;
        }
        case EX_CREATE_PICTURE:
        {
            eb->fPicture = new char;
            void *pointer = eb->fPicture;
            pictures.insert(pointer);
            ++pictureCreates;
            break;
        }
        case EX_DISPOSE_PICTURE:
        {
            void *pointer = eb->fPicture;
            assert(pictures.erase(pointer) == 1);
            delete (char *)pointer;
            ++pictureDisposes;
            break;
        }
        default:
            std::cerr << "Unexpected SDK selector " << selector << "\n";
            std::abort();
    }
}

@implementation FixtureWorkspace
+ (id)sharedWorkspace { return [[[self alloc] init] autorelease]; }
- (NSArray *)runningApplications
{
    NSMutableArray *result = [NSMutableArray array];
    for(int i = 0; i < appCount; ++i)
        [result addObject:@{@"NSApplicationName": @"fixture \u65e5 \U0001f600",
                           @"NSApplicationPath": @"/synthetic/fixture.app",
                           @"NSApplicationProcessIdentifier": @4242}];
    return result;
}
- (BOOL)openFile:(NSString *)file withApplication:(NSString *)application
{
    assert([file isEqualToString:@"/synthetic/document"]);
    assert([application isEqualToString:@"/synthetic/fixture.app"]);
    ++operations;
    return YES;
}
- (BOOL)openURLs:(NSArray *)urls withAppBundleIdentifier:(NSString *)identifier
        options:(NSWorkspaceLaunchOptions)options additionalEventParamDescriptor:(id)descriptor
        launchIdentifiers:(NSArray **)identifiers
{
    assert([urls count] == 1 && [identifier isEqualToString:@"fixture"]);
    assert(options == (NSWorkspaceLaunchAndPrint | NSWorkspaceLaunchWithoutActivation | NSWorkspaceLaunchAsync));
    assert(!descriptor && !identifiers);
    ++operations;
    return YES;
}
@end
@implementation FixtureBundle
- (id)initWithPath:(NSString *)path
{
    assert([path isEqualToString:@"/synthetic/fixture.app"]);
    return [super init];
}
- (NSString *)bundleIdentifier { return @"fixture"; }
@end
@implementation FixtureURL
- (id)initFileURLWithPath:(NSString *)path
{
    assert([path isEqualToString:@"/synthetic/fixture.app"]);
    [self release];
    return (id)[path copy];
}
@end
CFURLRef FixtureURLCreate(CFAllocatorRef, CFStringRef path, CFURLPathStyle, Boolean)
{ return (CFURLRef)CFStringCreateCopy(kCFAllocatorDefault, path); }
CFStringRef FixtureURLCopyPath(CFURLRef path, CFURLPathStyle)
{ return CFStringCreateCopy(kCFAllocatorDefault, (CFStringRef)path); }
OSStatus FixtureFindApplication(OSType, OSType, CFStringRef extension, LSRolesMask, FSRef *, CFURLRef *url)
{
    assert(CFEqual(extension, CFSTR("fixture")));
    *url = (CFURLRef)CFStringCreateCopy(kCFAllocatorDefault, CFSTR("/synthetic/fixture.app"));
    return noErr;
}

static void balanced()
{
    if(!strings.empty() || !handles.empty() || !refs.empty() || !pictures.empty())
    {
        std::cerr << "OWNER IMBALANCE strings=" << strings.size()
                  << " handles=" << handles.size() << " refs=" << refs.size()
                  << " pictures=" << pictures.size() << "\n";
        std::abort();
    }
}
template<class T> static void copyProbe(bool assignment)
{
    if constexpr(std::is_copy_constructible<T>::value && std::is_copy_assignable<T>::value)
    {
        T original;
        if(assignment) { T copy; copy = original; }
        else { T copy(original); }
    }
    else assert(!std::is_copy_constructible<T>::value && !std::is_copy_assignable<T>::value);
}
static void runCase(const std::string& name)
{
    const char *fixtures[] = {"", "ASCII", "\xE6\x97\xA5", "\xF0\x9F\x98\x80"};
    if(name == "scalar-setters")
    {
        for(bool empty : {false, true})
        {
            allocatedEmpty = empty;
            Ref *object = newRef();
            for(const char *text : fixtures)
            {
                CUTF16String utf = u16(text);
                ob_set_s(object, "key", text);
                assert(readString(object->properties.at(u16("key")).uValue.fString) == utf);
                ob_set_s(object, L"key", text);
                assert(readString(object->properties.at(u16("key")).uValue.fString) == utf);
                ob_set_a(object, L"key", &utf);
                assert(readString(object->properties.at(u16("key")).uValue.fString) == utf);
            }
            ob_set_a(object, L"key", L"wide \u65e5 \U0001f600");
            assert(readString(object->properties.at(u16("key")).uValue.fString) == u16("wide \xE6\x97\xA5 \xF0\x9F\x98\x80"));
            dropRef(object);
            balanced();
        }
    }
    else if(name == "picture-setter")
    {
        Ref *object = newRef();
        ob_set_p(object, L"key", PA_CreatePicture(nullptr, 0));
        void *stored = object->properties.at(u16("key")).uValue.fPicture;
        assert(pictures.count(stored));
        dropRef(object);
    }
    else if(name == "reference-setters")
    {
        Ref *object = newRef();
        ob_set_o(object, L"wide", newRef());
        ob_set_o(object, "narrow", newRef());
        ob_set_c(object, L"collection", newRef());
        ob_set_i(object, L"integer", 42);
        ob_set_b(object, L"boolean", true);
        ob_set_n(object, L"real", 42.5);
        dropRef(object);
    }
    else if(name == "property-getters" || name == "property-mismatches")
    {
        for(bool empty : {false, true})
        {
            allocatedEmpty = empty;
            Ref *object = newRef();
            if(name == "property-getters")
            {
                for(const char *text : fixtures)
                {
                    object->properties[u16("key")] = textValue(text);
                    CUTF8String output;
                    assert(ob_get_a(object, L"key", &output) && output == u8(text));
                    clear(object->properties.at(u16("key")));
                }
                PA_SetBooleanVariable(&object->properties[u16("key")], true);
                assert(ob_get_b(object, L"key"));
                PA_SetRealVariable(&object->properties[u16("key")], 42.5);
                assert(ob_get_n(object, L"key") == 42.5);
                Ref *child = newRef();
                PA_SetCollectionVariable(&object->properties[u16("key")], child);
                void *returned = ob_get_c(object, L"key");
                assert(returned == child && child->owners == 2);
                dropRef(returned);
                clear(object->properties.at(u16("key")));
            }
            else
            {
                for(int kind = 0; kind < 4; ++kind)
                {
                    PA_Variable& value = object->properties[u16("key")];
                    value.fType = eVK_Undefined;
                    if(kind == 0) value = textValue("owned");
                    if(kind == 1) PA_SetPictureVariable(&value, PA_CreatePicture(nullptr, 0));
                    if(kind == 2) PA_SetObjectVariable(&value, newRef());
                    if(kind == 3) PA_SetCollectionVariable(&value, newRef());
                    assert(!ob_get_b(object, L"key"));
                    assert(ob_get_n(object, L"key") == 0);
                    CUTF8String output;
                    ob_get_a(object, L"key", &output);
                    if(kind != 3) assert(ob_get_c(object, L"key") == nullptr);
                    clear(value);
                }
            }
            CUTF8String unchanged = u8("unchanged");
            assert(!ob_get_a(object, L"missing", &unchanged) && unchanged == u8("unchanged"));
            assert(!ob_is_defined(object, L"missing"));
            dropRef(object);
            balanced();
        }
    }
    else if(name == "property-errors")
    {
        Ref *object = newRef();
        object->properties[u16("key")] = textValue("owned");
        for(int mode = 0; mode < 3; ++mode)
        {
            failHas = mode == 0; failProperty = mode == 1; failString = mode == 2;
            for(int getter = 0; getter < (failString ? 1 : 4); ++getter)
            {
                bool threw = false;
                try {
                    CUTF8String output;
                    if(getter == 0) ob_get_a(object, L"key", &output);
                    if(getter == 1) ob_get_b(object, L"key");
                    if(getter == 2) ob_get_n(object, L"key");
                    if(getter == 3) ob_get_c(object, L"key");
                } catch(const std::runtime_error&) { threw = true; }
                assert(threw);
            }
        }
        failHas = failProperty = failString = false;
        dropRef(object);
    }
    else if(name == "stringify-errors" || name == "stringify-success")
    {
        Ref *object = newRef();
        if(name == "stringify-success")
        {
            CUTF8String output;
            ob_stringify(object, &output);
            assert(output == u8("synthetic \xE6\x97\xA5 \xF0\x9F\x98\x80"));
        }
        else
        {
            for(int failure = 0; failure < 7; ++failure)
            {
                failHandleCountdown = failure < 2 ? failure + 1 : 0;
                failCommand = failure == 2 ? 1225 : failure == 3 ? 1217 : 0;
                wrongCommand = failure == 4 ? 1225 : failure == 5 ? 1217 : 0;
                failString = failure == 6;
                bool threw = false;
                CUTF8String output = u8("unchanged");
                try { ob_stringify(object, &output); }
                catch(const std::runtime_error&) { threw = true; }
                assert(threw && output == u8("unchanged"));
                failHandleCountdown = failCommand = wrongCommand = 0; failString = false;
            }
        }
        dropRef(object);
    }
    else if(name == "arrays")
    {
        for(bool empty : {false, true})
        {
            allocatedEmpty = empty;
            PA_Variable array = PA_CreateVariable(eVK_ArrayUnicode);
            BytePtr parameter[] = {(BytePtr)&array};
            ARRAY_TEXT source;
            for(const char *text : fixtures) { CUTF16String utf = u16(text); source.appendUTF16String(&utf); }
            for(int repeat = 0; repeat < 20; ++repeat)
            {
                source.toParamAtIndex(parameter, 1);
                assert(array.uValue.fArray.fNbElements == 3);
                std::vector<CUTF16String> churn(100, u16("allocator churn"));
                std::set<PA_Unichar *> distinct;
                for(int i = 0; i < 4; ++i)
                {
                    PA_Unistring str = PA_GetStringInArray(array, i);
                    assert(readString(str) == u16(fixtures[i]));
                    PA_Unichar *pointer = str.fString;
                    if(pointer) assert(distinct.insert(pointer).second);
                }
                ARRAY_TEXT copied;
                copied.fromParamAtIndex(parameter, 1);
                PA_Unistring replacement = makeString(u16("replacement"));
                PA_SetStringInArray(array, 1, &replacement);
                CUTF16String original;
                copied.copyUTF16StringAtIndex(&original, 1);
                assert(original == u16("ASCII"));
            }
            for(int rejection = 0; rejection < 5; ++rejection)
            {
                PA_Variable target = array;
                int index = 0;
                if(rejection == 0) target.fType = eVK_Longint;
                if(rejection == 1) target.uValue.fArray.fData = nullptr;
                if(rejection == 2) index = -1;
                if(rejection == 3) index = 4;
                PA_Unistring owner = makeString(u16("rejected"));
                PA_SetStringInArray(target, index, rejection == 4 ? nullptr : &owner);
                assert(readString(owner) == u16("rejected"));
                PA_DisposeUnistring(&owner);
            }
            PA_ResizeArray(&array, 0);
            PA_ClearVariable(&array);
            balanced();
        }
    }
    else if(name == "resize-limit")
    {
        PA_Variable array = PA_CreateVariable(eVK_ArrayUnicode);
        PA_Handle handle = array.uValue.fArray.fData;
        size_t physical = handles.at(handle);
        failResize = true;
        PA_ResizeArray(&array, 5);
        assert(PA_GetLastError() != eER_NoErr);
        assert(array.uValue.fArray.fNbElements == 5 && handles.at(handle) == physical);
        failResize = false;
        array.uValue.fArray.fNbElements = 0; // fixture cleanup only, not a production recovery
        PA_ClearVariable(&array);
    }
    else if(name == "text")
    {
        for(bool empty : {false, true})
        {
            allocatedEmpty = empty;
            for(const char *text : fixtures)
            {
                C_TEXT value;
                value.setUTF8String((const uint8_t *)text, (uint32_t)strlen(text));
                assert(CUTF16String(value.getUTF16StringPtr(), value.getUTF16Length()) == u16(text));
                CUTF8String output;
                value.copyUTF8String(&output);
                assert(output == u8(text));
                PA_Unistring destination = makeString(u16("old"));
                BytePtr parameter[] = {(BytePtr)&destination};
                value.toParamAtIndex(parameter, 1);
                assert(readString(destination) == u16(text));
                PA_Unistring *result = &destination;
                value.setReturn((sLONG_PTR *)&result);
                assert(readString(destination) == u16(text));
                PA_DisposeUnistring(&destination);
            }
        }
    }
    else if(name == "dispatcher")
    {
        for(int count : {0, 3})
        {
            appCount = count;
            PA_CollectionRef output = nullptr;
            FourDPackex(2, nullptr, nullptr, &output);
            Ref *collection = (Ref *)output;
            assert(collection && collection->elements.size() == (size_t)count);
            for(auto& element : collection->elements)
            {
                Ref *object = (Ref *)element.uValue.fObject;
                assert(object->owners == 1);
                assert(readString(object->properties.at(u16("name")).uValue.fString) == u16("fixture \xE6\x97\xA5 \xF0\x9F\x98\x80"));
                assert(readString(object->properties.at(u16("path")).uValue.fString) == u16("/synthetic/fixture.app"));
                assert(object->properties.at(u16("pid")).uValue.fReal == 4242);
            }
            dropRef(output);
        }
        PA_Unistring document = makeString(u16("/synthetic/document"));
        PA_Unistring application = makeString(u16("/synthetic/fixture.app"));
        BytePtr args[] = {(BytePtr)&document, (BytePtr)&application};
        for(int selector : {3, 4}) FourDPackex(selector, args, nullptr, nullptr);
        assert(operations == 2);
        PA_Unistring extension = makeString(u16("/synthetic/document.fixture"));
        PA_Unistring result = makeString(u16(""));
        PA_Unistring *resultPtr = &result;
        BytePtr findArgs[] = {(BytePtr)&extension};
        FourDPackex(1, findArgs, nullptr, &resultPtr);
        assert(readString(result) == u16("/synthetic/fixture.app"));
        for(PA_Unistring *s : {&document, &application, &extension, &result}) PA_DisposeUnistring(s);
    }
    else if(name == "blob")
    {
        const uint8_t bytes[] = {0, 1, 255};
        C_BLOB value;
        value.setBytes(bytes, sizeof(bytes));
        PA_Handle handle = nullptr;
        BytePtr args[] = {(BytePtr)&handle};
        value.toParamAtIndex(args, 1);
        assert(handles.at(handle) == sizeof(bytes) && memcmp(*handle, bytes, sizeof(bytes)) == 0);
        C_BLOB copied;
        copied.fromParamAtIndex(args, 1);
        assert(copied.getBytesLength() == sizeof(bytes));
        PA_DisposeHandle(handle);
        C_LONGINT number;
        number.setIntValue(42);
        int destination = 0;
        BytePtr numeric[] = {(BytePtr)&destination};
        number.toParamAtIndex(numeric, 1);
        assert(destination == 42);
    }
    else if(name == "array-copy" || name == "array-assignment") copyProbe<ARRAY_TEXT>(name == "array-assignment");
    else if(name == "blob-copy" || name == "blob-assignment") copyProbe<C_BLOB>(name == "blob-assignment");
    else std::abort();
    static_assert(!std::is_copy_constructible<C_TEXT>::value && !std::is_copy_assignable<C_TEXT>::value);
    balanced();
    std::cout << name << " balanced creates/disposes: strings=" << stringCreates << "/" << stringDisposes
              << " handles=" << handleCreates << "/" << handleDisposes
              << " refs=" << refCreates << "/" << refDisposes
              << " pictures=" << pictureCreates << "/" << pictureDisposes << "\n";
}
int main(int argc, char **argv)
{
    assert(argc == 2);
    gCall4D = host;
    @autoreleasepool { runCase(argv[1]); }
}
