/// <reference types="node" />
export type Json = null | boolean | number | string | Json[] | { [key: string]: Json };
export interface RawResult { status: number; data: Buffer }
export class NativeError extends Error { constructor(status: number, data: Json); status: number; kind?: string; data: Json }
export class Cancellation { constructor(); cancel(): void; close(): void }
export function callRaw(input: Uint8Array, token?: Cancellation): RawResult;
export function callRawAsync(input: Uint8Array, token?: Cancellation): Promise<RawResult>;
export function call(input: Json, token?: Cancellation): Json;
export function callAsync(input: Json, token?: Cancellation): Promise<Json>;
