package ziggify
/*
#cgo CFLAGS: -I${SRCDIR}
#cgo LDFLAGS: -L${SRCDIR}/zig-out/lib -lziggify_port -Wl,-rpath,${SRCDIR}/zig-out/lib
#include <stdlib.h>
#include "ziggify.h"
*/
import "C"
import (
 "bytes"
 "encoding/json"
 "errors"
 "sync/atomic"
 "unsafe"
)
type Cancellation struct { handle atomic.Uint64 }
func NewCancellation() (*Cancellation,error) {
 c:=&Cancellation{}; c.handle.Store(uint64(C.ziggify_cancel_new()))
 if c.handle.Load()==0 {return nil,errors.New("native allocation failed")};return c,nil
}
func (c *Cancellation) Cancel() error {if C.ziggify_cancel(C.uint64_t(c.handle.Load()))!=0{return errors.New("closed cancellation handle")};return nil}
func (c *Cancellation) Close() {if id:=c.handle.Swap(0);id!=0 {C.ziggify_cancel_free(C.uint64_t(id))}}
func CallRaw(input []byte, cancellation *Cancellation) (uint32,[]byte) {
 if len(input)>16*1024*1024 {return 5,[]byte(`{"error":{"type":"InputTooLarge"}}`)}
 var token uint64
 if cancellation!=nil {token=cancellation.handle.Load(); if token==0{return 6,[]byte(`{"error":{"type":"InvalidHandle"}}`)}}
 data:=C.CBytes(input);defer C.free(data)
 var result C.ziggify_result
 status:=C.ziggify_call((*C.uint8_t)(data),C.size_t(len(input)),C.uint64_t(token),&result)
 defer C.ziggify_release(&result)
 return uint32(status),C.GoBytes(unsafe.Pointer(result.data),C.int(result.len))
}
type NativeError struct {Status uint32; Data json.RawMessage}
func(e *NativeError) Error() string {return string(e.Data)}
func Call(input any,cancellation *Cancellation)(any,error) {
 request,err:=json.Marshal(input);if err!=nil{return nil,err}
 status,data:=CallRaw(request,cancellation)
 if status!=0{return nil,&NativeError{Status:status,Data:data}}
 var value any;decoder:=json.NewDecoder(bytes.NewReader(data));decoder.UseNumber()
 err=decoder.Decode(&value);return value,err
}
