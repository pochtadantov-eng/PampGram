// Generates the Ed25519 key pair for the /access gate.
//   node scripts/gen-access-key.mjs
// Prints:
//   - the PRIVATE key (PKCS8, base64) -> `wrangler secret put ACCESS_SIGNING_KEY`, never commit it;
//   - the PUBLIC key (raw 32 bytes, base64) -> `accessPublicKeyBase64` in
//     mod/components/PampGramCore/Sources/PampGramAccessGate.swift, rebuild the app.
// Rotating the pair locks every installed copy of the previous build until it is updated.

const pair = await crypto.subtle.generateKey({ name: "Ed25519" }, true, ["sign", "verify"]);
const b64 = (bytes) => Buffer.from(bytes).toString("base64");
const privateKey = b64(new Uint8Array(await crypto.subtle.exportKey("pkcs8", pair.privateKey)));
const publicKey = b64(new Uint8Array(await crypto.subtle.exportKey("raw", pair.publicKey)));
console.log(`PRIVATE (secret ACCESS_SIGNING_KEY): ${privateKey}`);
console.log(`PUBLIC  (accessPublicKeyBase64):     ${publicKey}`);
