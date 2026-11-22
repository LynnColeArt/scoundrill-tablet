const path = require('node:path');
const addon = {exports:{}};
const suffix = process.platform === 'darwin' ? 'libziggify_node.dylib' : process.platform === 'win32' ? 'ziggify_node.dll' : 'libziggify_node.so';
process.dlopen(addon, path.join(__dirname,'zig-out','lib',suffix));
const native = addon.exports;
class NativeError extends Error {
    constructor(status,data) { super(data?.error?.type || 'NativeError'); this.name='NativeError'; this.status=status; this.data=data; this.kind=data?.error?.type; }
}
const finalizer = new FinalizationRegistry(handle => native.cancelFree(handle));
class Cancellation {
    constructor() { this.handle=native.cancelNew(); finalizer.register(this,this.handle,this); }
    cancel() { if(!this.handle || native.cancel(this.handle)) throw new Error('closed cancellation handle'); }
    close() { if(this.handle) {finalizer.unregister(this);native.cancelFree(this.handle);this.handle=0n;} }
}
function handle(token) {if(token && !token.handle) throw new Error('closed cancellation handle');return token?.handle || 0n;}
function unwrap(result) {const value=result.data.length ? JSON.parse(result.data.toString('utf8')) : null; if(result.status)throw new NativeError(result.status,value);return value;}
function encode(value) {return Buffer.from(JSON.stringify(value),'utf8');}
async function rawAsync(input,token) {
    const result=await native.callRawAsync(Buffer.from(input),handle(token));
    // Keep the wrapper reachable while queued work is waiting to acquire its
    // native cancellation reference; finalization must not close it early.
    if(token && typeof token.handle!=='bigint') throw new TypeError('invalid cancellation wrapper');
    return result;
}
module.exports={NativeError,Cancellation,
    callRaw:(input,token)=>native.callRaw(Buffer.from(input),handle(token)),
    callRawAsync:rawAsync,
    call:(input,token)=>unwrap(native.callRaw(encode(input),handle(token))),
    callAsync:(input,token)=>rawAsync(encode(input),token).then(unwrap)};
