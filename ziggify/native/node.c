//go:build ignore

#include <node_api.h>
#include <stdlib.h>
#include <string.h>
#include "ziggify.h"
#define CHECK(x) do { if ((x) != napi_ok) { napi_throw_error(env, NULL, "Node-API failure"); return NULL; } } while(0)
typedef struct { napi_async_work work; napi_deferred deferred; uint8_t *input; size_t length; uint64_t cancel; uint32_t status; ziggify_result result; } Job;
static int args(napi_env env, napi_callback_info info, const uint8_t **input, size_t *length, uint64_t *cancel) {
    size_t argc=2; napi_value argv[2]; bool buffer=false;
    if (napi_get_cb_info(env,info,&argc,argv,NULL,NULL)!=napi_ok || argc<1 || napi_is_buffer(env,argv[0],&buffer)!=napi_ok || !buffer) {
        napi_throw_type_error(env,NULL,"expected a Buffer"); return 0;
    }
    void *data=NULL;
    if (napi_get_buffer_info(env,argv[0],&data,length)!=napi_ok) return 0;
    *input=data; *cancel=0;
    if (argc>1) {
        bool lossless=false;
        if(napi_get_value_bigint_uint64(env,argv[1],cancel,&lossless)!=napi_ok || !lossless) {
            napi_throw_type_error(env,NULL,"cancellation must be an unsigned 64-bit handle"); return 0;
        }
    }
    if (*length>ZIGGIFY_MAX_BYTES) { napi_throw_range_error(env,NULL,"native input limit exceeded"); return 0; }
    return 1;
}
static napi_value result_value(napi_env env,uint32_t status,ziggify_result *result) {
    napi_value value,code,data;
    if(napi_create_object(env,&value)!=napi_ok || napi_create_uint32(env,status,&code)!=napi_ok ||
       napi_create_buffer_copy(env,result->len,result->data,NULL,&data)!=napi_ok ||
       napi_set_named_property(env,value,"status",code)!=napi_ok || napi_set_named_property(env,value,"data",data)!=napi_ok) return NULL;
    return value;
}
static napi_value call_raw(napi_env env,napi_callback_info info) {
    const uint8_t *input; size_t length; uint64_t cancel;
    if(!args(env,info,&input,&length,&cancel)) return NULL;
    ziggify_result result={0}; uint32_t status=ziggify_call(input,length,cancel,&result);
    napi_value value=result_value(env,status,&result);
    ziggify_release(&result);
    if(!value) napi_throw_error(env,NULL,"could not allocate Node result");
    return value;
}
static void execute(napi_env env,void *data) {
    (void)env; Job *job=data;
    job->status=ziggify_call(job->input,job->length,job->cancel,&job->result);
}
static void complete(napi_env env,napi_status status,void *data) {
    Job *job=data;
    napi_value value=status==napi_ok ? result_value(env,job->status,&job->result):NULL;
    if(value) napi_resolve_deferred(env,job->deferred,value);
    else {
        napi_value message,error;
        if(napi_create_string_utf8(env,"native async work failed",NAPI_AUTO_LENGTH,&message)==napi_ok && napi_create_error(env,NULL,message,&error)==napi_ok)
            napi_reject_deferred(env,job->deferred,error);
    }
    ziggify_release(&job->result); free(job->input);
    napi_delete_async_work(env,job->work); free(job);
}
static napi_value call_async(napi_env env,napi_callback_info info) {
    const uint8_t *input; size_t length; uint64_t cancel;
    if(!args(env,info,&input,&length,&cancel)) return NULL;
    Job *job=calloc(1,sizeof(*job));
    if(!job) { napi_throw_error(env,NULL,"out of memory"); return NULL; }
    job->input=malloc(length ? length:1);
    if(!job->input) { free(job); napi_throw_error(env,NULL,"out of memory"); return NULL; }
    if(length) memcpy(job->input,input,length); job->length=length; job->cancel=cancel;
    napi_value promise,name;
    if(napi_create_promise(env,&job->deferred,&promise)!=napi_ok) {
        free(job->input);free(job);napi_throw_error(env,NULL,"cannot allocate promise");return NULL;
    }
    if(napi_create_string_utf8(env,"ziggify",NAPI_AUTO_LENGTH,&name)!=napi_ok ||
       napi_create_async_work(env,NULL,name,execute,complete,job,&job->work)!=napi_ok ||
       napi_queue_async_work(env,job->work)!=napi_ok) {
        napi_value message,error;
        if(napi_create_string_utf8(env,"cannot start native async work",NAPI_AUTO_LENGTH,&message)==napi_ok && napi_create_error(env,NULL,message,&error)==napi_ok)
            napi_reject_deferred(env,job->deferred,error);
        if(job->work)napi_delete_async_work(env,job->work);
        free(job->input);free(job);return promise;
    }
    return promise;
}
static napi_value cancel_new(napi_env env,napi_callback_info info) {
    (void)info; uint64_t handle=ziggify_cancel_new();
    if(!handle) {napi_throw_error(env,NULL,"out of memory"); return NULL;}
    napi_value value;
    if(napi_create_bigint_uint64(env,handle,&value)!=napi_ok) {ziggify_cancel_free(handle);return NULL;}
    return value;
}
static napi_value token_op(napi_env env,napi_callback_info info,int release) {
    size_t argc=1;napi_value arg,result;uint64_t handle;bool lossless;
    CHECK(napi_get_cb_info(env,info,&argc,&arg,NULL,NULL));
    if(argc!=1) {napi_throw_type_error(env,NULL,"expected handle");return NULL;}
    CHECK(napi_get_value_bigint_uint64(env,arg,&handle,&lossless));
    if(!lossless) {napi_throw_range_error(env,NULL,"invalid handle");return NULL;}
    CHECK(napi_create_uint32(env,release?ziggify_cancel_free(handle):ziggify_cancel(handle),&result)); return result;
}
static napi_value cancel(napi_env env,napi_callback_info info) {return token_op(env,info,0);}
static napi_value cancel_free(napi_env env,napi_callback_info info) {return token_op(env,info,1);}
static napi_value init(napi_env env,napi_value exports) {
    if(ziggify_abi_version()!=ZIGGIFY_ABI_VERSION) {napi_throw_error(env,NULL,"unsupported ABI version");return NULL;}
    napi_property_descriptor properties[]={
        {"callRaw",NULL,call_raw,NULL,NULL,NULL,napi_default,NULL},
        {"callRawAsync",NULL,call_async,NULL,NULL,NULL,napi_default,NULL},
        {"cancelNew",NULL,cancel_new,NULL,NULL,NULL,napi_default,NULL},
        {"cancel",NULL,cancel,NULL,NULL,NULL,napi_default,NULL},
        {"cancelFree",NULL,cancel_free,NULL,NULL,NULL,napi_default,NULL}};
    CHECK(napi_define_properties(env,exports,sizeof(properties)/sizeof(properties[0]),properties));return exports;
}
NAPI_MODULE(NODE_GYP_MODULE_NAME,init)
