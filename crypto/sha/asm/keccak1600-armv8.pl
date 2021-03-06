#!/usr/bin/env perl
# Copyright 2017 The OpenSSL Project Authors. All Rights Reserved.
#
# Licensed under the OpenSSL license (the "License").  You may not use
# this file except in compliance with the License.  You can obtain a copy
# in the file LICENSE in the source distribution or at
# https://www.openssl.org/source/license.html
#
# ====================================================================
# Written by Andy Polyakov <appro@openssl.org> for the OpenSSL
# project. The module is, however, dual licensed under OpenSSL and
# CRYPTOGAMS licenses depending on where you obtain it. For further
# details see http://www.openssl.org/~appro/cryptogams/.
# ====================================================================
#
# Keccak-1600 for ARMv8.
#
# June 2017.
#
# This is straightforward KECCAK_1X_ALT implementation. It makes no
# sense to attempt SIMD/NEON implementation for following reason.
# 64-bit lanes of vector registers can't be addressed as easily as in
# 32-bit mode. This means that 64-bit NEON is bound to be slower than
# 32-bit NEON, and this implementation is faster than 32-bit NEON on
# same processor. Even though it takes more scalar xor's and andn's,
# it gets compensated by availability of rotate. Not to forget that
# most processors achieve higher issue rate with scalar instructions.
#
######################################################################
# Numbers are cycles per processed byte.
#
#		r=1088(*)
#
# Cortex-A53	13
# Cortex-A57	12
# X-Gene	14
# Mongoose	10
# Denver	7.8
# Apple A7	7.2
#
# (*)	Corresponds to SHA3-256. No improvement coefficients are listed
#	because they vary too much from compiler to compiler. Newer
#	compiler does much better and improvement varies from 5% on
#	Cortex-A57 to 25% on Cortex-A53. While in comparison to older
#	compiler this code is at least 2x faster...

$flavour = shift;
$output  = shift;

$0 =~ m/(.*[\/\\])[^\/\\]+$/; $dir=$1;
( $xlate="${dir}arm-xlate.pl" and -f $xlate ) or
( $xlate="${dir}../../perlasm/arm-xlate.pl" and -f $xlate) or
die "can't locate arm-xlate.pl";

open OUT,"| \"$^X\" $xlate $flavour $output";
*STDOUT=*OUT;

my @A = map([ "x$_", "x".($_+1), "x".($_+2), "x".($_+3), "x".($_+4) ],
            (0, 5, 10, 15, 20));
   $A[3][3] = "x25"; # x18 is reserved

my @C = map("x$_", (26,27,28,30));

my @rhotates = ([  0,  1, 62, 28, 27 ],
                [ 36, 44,  6, 55, 20 ],
                [  3, 10, 43, 25, 39 ],
                [ 41, 45, 15, 21,  8 ],
                [ 18,  2, 61, 56, 14 ]);

$code.=<<___;
.text

.align 8	// strategic alignment and padding that allows to use
		// address value as loop termination condition...
	.quad	0,0,0,0,0,0,0,0
.type	iotas,%object
iotas:
	.quad	0x0000000000000001
	.quad	0x0000000000008082
	.quad	0x800000000000808a
	.quad	0x8000000080008000
	.quad	0x000000000000808b
	.quad	0x0000000080000001
	.quad	0x8000000080008081
	.quad	0x8000000000008009
	.quad	0x000000000000008a
	.quad	0x0000000000000088
	.quad	0x0000000080008009
	.quad	0x000000008000000a
	.quad	0x000000008000808b
	.quad	0x800000000000008b
	.quad	0x8000000000008089
	.quad	0x8000000000008003
	.quad	0x8000000000008002
	.quad	0x8000000000000080
	.quad	0x000000000000800a
	.quad	0x800000008000000a
	.quad	0x8000000080008081
	.quad	0x8000000000008080
	.quad	0x0000000080000001
	.quad	0x8000000080008008
.size	iotas,.-iotas

.type	KeccakF1600_int,%function
.align	5
KeccakF1600_int:
	adr	$C[2],iotas
	stp	$C[2],x30,[sp,#16]		// 32 bytes on top are mine
	b	.Loop
.align	4
.Loop:
	////////////////////////////////////////// Theta
	eor	$C[0],$A[0][0],$A[1][0]
	stp	$A[0][4],$A[1][4],[sp,#0]	// offload pair...
	eor	$C[1],$A[0][1],$A[1][1]
	eor	$C[2],$A[0][2],$A[1][2]
	eor	$C[3],$A[0][3],$A[1][3]
___
	$C[4]=$A[0][4];
	$C[5]=$A[1][4];
$code.=<<___;
	eor	$C[4],$A[0][4],$A[1][4]
	eor	$C[0],$C[0],$A[2][0]
	eor	$C[1],$C[1],$A[2][1]
	eor	$C[2],$C[2],$A[2][2]
	eor	$C[3],$C[3],$A[2][3]
	eor	$C[4],$C[4],$A[2][4]
	eor	$C[0],$C[0],$A[3][0]
	eor	$C[1],$C[1],$A[3][1]
	eor	$C[2],$C[2],$A[3][2]
	eor	$C[3],$C[3],$A[3][3]
	eor	$C[4],$C[4],$A[3][4]
	eor	$C[0],$C[0],$A[4][0]
	eor	$C[2],$C[2],$A[4][2]
	eor	$C[1],$C[1],$A[4][1]
	eor	$C[3],$C[3],$A[4][3]
	eor	$C[4],$C[4],$A[4][4]

	eor	$C[5],$C[0],$C[2],ror#63

	eor	$A[0][1],$A[0][1],$C[5]
	eor	$A[1][1],$A[1][1],$C[5]
	eor	$A[2][1],$A[2][1],$C[5]
	eor	$A[3][1],$A[3][1],$C[5]
	eor	$A[4][1],$A[4][1],$C[5]

	eor	$C[5],$C[1],$C[3],ror#63
	eor	$C[2],$C[2],$C[4],ror#63
	eor	$C[3],$C[3],$C[0],ror#63
	eor	$C[4],$C[4],$C[1],ror#63

	eor	$C[1],   $A[0][2],$C[5]		// mov	$C[1],$A[0][2]
	eor	$A[1][2],$A[1][2],$C[5]
	eor	$A[2][2],$A[2][2],$C[5]
	eor	$A[3][2],$A[3][2],$C[5]
	eor	$A[4][2],$A[4][2],$C[5]

	eor	$A[0][0],$A[0][0],$C[4]
	eor	$A[1][0],$A[1][0],$C[4]
	eor	$A[2][0],$A[2][0],$C[4]
	eor	$A[3][0],$A[3][0],$C[4]
	eor	$A[4][0],$A[4][0],$C[4]
___
	$C[4]=undef;
	$C[5]=undef;
$code.=<<___;
	ldp	$A[0][4],$A[1][4],[sp,#0]	// re-load offloaded data
	eor	$C[0],   $A[0][3],$C[2]		// mov	$C[0],$A[0][3]
	eor	$A[1][3],$A[1][3],$C[2]
	eor	$A[2][3],$A[2][3],$C[2]
	eor	$A[3][3],$A[3][3],$C[2]
	eor	$A[4][3],$A[4][3],$C[2]

	eor	$C[2],   $A[0][4],$C[3]		// mov	$C[2],$A[0][4]
	eor	$A[1][4],$A[1][4],$C[3]
	eor	$A[2][4],$A[2][4],$C[3]
	eor	$A[3][4],$A[3][4],$C[3]
	eor	$A[4][4],$A[4][4],$C[3]

	////////////////////////////////////////// Rho+Pi
	mov	$C[3],$A[0][1]
	ror	$A[0][1],$A[1][1],#64-$rhotates[1][1]
	//mov	$C[1],$A[0][2]
	ror	$A[0][2],$A[2][2],#64-$rhotates[2][2]
	//mov	$C[0],$A[0][3]
	ror	$A[0][3],$A[3][3],#64-$rhotates[3][3]
	//mov	$C[2],$A[0][4]
	ror	$A[0][4],$A[4][4],#64-$rhotates[4][4]

	ror	$A[1][1],$A[1][4],#64-$rhotates[1][4]
	ror	$A[2][2],$A[2][3],#64-$rhotates[2][3]
	ror	$A[3][3],$A[3][2],#64-$rhotates[3][2]
	ror	$A[4][4],$A[4][1],#64-$rhotates[4][1]

	ror	$A[1][4],$A[4][2],#64-$rhotates[4][2]
	ror	$A[2][3],$A[3][4],#64-$rhotates[3][4]
	ror	$A[3][2],$A[2][1],#64-$rhotates[2][1]
	ror	$A[4][1],$A[1][3],#64-$rhotates[1][3]

	ror	$A[4][2],$A[2][4],#64-$rhotates[2][4]
	ror	$A[3][4],$A[4][3],#64-$rhotates[4][3]
	ror	$A[2][1],$A[1][2],#64-$rhotates[1][2]
	ror	$A[1][3],$A[3][1],#64-$rhotates[3][1]

	ror	$A[2][4],$A[4][0],#64-$rhotates[4][0]
	ror	$A[4][3],$A[3][0],#64-$rhotates[3][0]
	ror	$A[1][2],$A[2][0],#64-$rhotates[2][0]
	ror	$A[3][1],$A[1][0],#64-$rhotates[1][0]

	ror	$A[1][0],$C[0],#64-$rhotates[0][3]
	ror	$A[2][0],$C[3],#64-$rhotates[0][1]
	ror	$A[3][0],$C[2],#64-$rhotates[0][4]
	ror	$A[4][0],$C[1],#64-$rhotates[0][2]

	////////////////////////////////////////// Chi+Iota
	bic	$C[0],$A[0][2],$A[0][1]
	bic	$C[1],$A[0][3],$A[0][2]
	bic	$C[2],$A[0][0],$A[0][4]
	bic	$C[3],$A[0][1],$A[0][0]
	eor	$A[0][0],$A[0][0],$C[0]
	bic	$C[0],$A[0][4],$A[0][3]
	eor	$A[0][1],$A[0][1],$C[1]
	 ldr	$C[1],[sp,#16]
	eor	$A[0][3],$A[0][3],$C[2]
	eor	$A[0][4],$A[0][4],$C[3]
	eor	$A[0][2],$A[0][2],$C[0]
	 ldr	$C[3],[$C[1]],#8		// Iota[i++]

	bic	$C[0],$A[1][2],$A[1][1]
	 tst	$C[1],#255			// are we done?
	 str	$C[1],[sp,#16]
	bic	$C[1],$A[1][3],$A[1][2]
	bic	$C[2],$A[1][0],$A[1][4]
	 eor	$A[0][0],$A[0][0],$C[3]		// A[0][0] ^= Iota
	bic	$C[3],$A[1][1],$A[1][0]
	eor	$A[1][0],$A[1][0],$C[0]
	bic	$C[0],$A[1][4],$A[1][3]
	eor	$A[1][1],$A[1][1],$C[1]
	eor	$A[1][3],$A[1][3],$C[2]
	eor	$A[1][4],$A[1][4],$C[3]
	eor	$A[1][2],$A[1][2],$C[0]

	bic	$C[0],$A[2][2],$A[2][1]
	bic	$C[1],$A[2][3],$A[2][2]
	bic	$C[2],$A[2][0],$A[2][4]
	bic	$C[3],$A[2][1],$A[2][0]
	eor	$A[2][0],$A[2][0],$C[0]
	bic	$C[0],$A[2][4],$A[2][3]
	eor	$A[2][1],$A[2][1],$C[1]
	eor	$A[2][3],$A[2][3],$C[2]
	eor	$A[2][4],$A[2][4],$C[3]
	eor	$A[2][2],$A[2][2],$C[0]

	bic	$C[0],$A[3][2],$A[3][1]
	bic	$C[1],$A[3][3],$A[3][2]
	bic	$C[2],$A[3][0],$A[3][4]
	bic	$C[3],$A[3][1],$A[3][0]
	eor	$A[3][0],$A[3][0],$C[0]
	bic	$C[0],$A[3][4],$A[3][3]
	eor	$A[3][1],$A[3][1],$C[1]
	eor	$A[3][3],$A[3][3],$C[2]
	eor	$A[3][4],$A[3][4],$C[3]
	eor	$A[3][2],$A[3][2],$C[0]

	bic	$C[0],$A[4][2],$A[4][1]
	bic	$C[1],$A[4][3],$A[4][2]
	bic	$C[2],$A[4][0],$A[4][4]
	bic	$C[3],$A[4][1],$A[4][0]
	eor	$A[4][0],$A[4][0],$C[0]
	bic	$C[0],$A[4][4],$A[4][3]
	eor	$A[4][1],$A[4][1],$C[1]
	eor	$A[4][3],$A[4][3],$C[2]
	eor	$A[4][4],$A[4][4],$C[3]
	eor	$A[4][2],$A[4][2],$C[0]

	bne	.Loop

	ldr	x30,[sp,#24]
	ret
.size	KeccakF1600_int,.-KeccakF1600_int

.type	KeccakF1600,%function
.align	5
KeccakF1600:
	stp	x29,x30,[sp,#-128]!
	add	x29,sp,#0
	stp	x19,x20,[sp,#16]
	stp	x21,x22,[sp,#32]
	stp	x23,x24,[sp,#48]
	stp	x25,x26,[sp,#64]
	stp	x27,x28,[sp,#80]
	sub	sp,sp,#48

	str	x0,[sp,#32]			// offload argument
	mov	$C[0],x0
	ldp	$A[0][0],$A[0][1],[x0,#16*0]
	ldp	$A[0][2],$A[0][3],[$C[0],#16*1]
	ldp	$A[0][4],$A[1][0],[$C[0],#16*2]
	ldp	$A[1][1],$A[1][2],[$C[0],#16*3]
	ldp	$A[1][3],$A[1][4],[$C[0],#16*4]
	ldp	$A[2][0],$A[2][1],[$C[0],#16*5]
	ldp	$A[2][2],$A[2][3],[$C[0],#16*6]
	ldp	$A[2][4],$A[3][0],[$C[0],#16*7]
	ldp	$A[3][1],$A[3][2],[$C[0],#16*8]
	ldp	$A[3][3],$A[3][4],[$C[0],#16*9]
	ldp	$A[4][0],$A[4][1],[$C[0],#16*10]
	ldp	$A[4][2],$A[4][3],[$C[0],#16*11]
	ldr	$A[4][4],[$C[0],#16*12]

	bl	KeccakF1600_int

	ldr	$C[0],[sp,#32]
	stp	$A[0][0],$A[0][1],[$C[0],#16*0]
	stp	$A[0][2],$A[0][3],[$C[0],#16*1]
	stp	$A[0][4],$A[1][0],[$C[0],#16*2]
	stp	$A[1][1],$A[1][2],[$C[0],#16*3]
	stp	$A[1][3],$A[1][4],[$C[0],#16*4]
	stp	$A[2][0],$A[2][1],[$C[0],#16*5]
	stp	$A[2][2],$A[2][3],[$C[0],#16*6]
	stp	$A[2][4],$A[3][0],[$C[0],#16*7]
	stp	$A[3][1],$A[3][2],[$C[0],#16*8]
	stp	$A[3][3],$A[3][4],[$C[0],#16*9]
	stp	$A[4][0],$A[4][1],[$C[0],#16*10]
	stp	$A[4][2],$A[4][3],[$C[0],#16*11]
	str	$A[4][4],[$C[0],#16*12]

	ldp	x19,x20,[x29,#16]
	add	sp,sp,#48
	ldp	x21,x22,[x29,#32]
	ldp	x23,x24,[x29,#48]
	ldp	x25,x26,[x29,#64]
	ldp	x27,x28,[x29,#80]
	ldp	x29,x30,[sp],#128
	ret
.size	KeccakF1600,.-KeccakF1600

.globl	SHA3_absorb
.type	SHA3_absorb,%function
.align	5
SHA3_absorb:
	stp	x29,x30,[sp,#-128]!
	add	x29,sp,#0
	stp	x19,x20,[sp,#16]
	stp	x21,x22,[sp,#32]
	stp	x23,x24,[sp,#48]
	stp	x25,x26,[sp,#64]
	stp	x27,x28,[sp,#80]
	sub	sp,sp,#64

	stp	x0,x1,[sp,#32]			// offload arguments
	stp	x2,x3,[sp,#48]

	mov	$C[0],x0			// uint64_t A[5][5]
	mov	$C[1],x1			// const void *inp
	mov	$C[2],x2			// size_t len
	mov	$C[3],x3			// size_t bsz
	ldp	$A[0][0],$A[0][1],[$C[0],#16*0]
	ldp	$A[0][2],$A[0][3],[$C[0],#16*1]
	ldp	$A[0][4],$A[1][0],[$C[0],#16*2]
	ldp	$A[1][1],$A[1][2],[$C[0],#16*3]
	ldp	$A[1][3],$A[1][4],[$C[0],#16*4]
	ldp	$A[2][0],$A[2][1],[$C[0],#16*5]
	ldp	$A[2][2],$A[2][3],[$C[0],#16*6]
	ldp	$A[2][4],$A[3][0],[$C[0],#16*7]
	ldp	$A[3][1],$A[3][2],[$C[0],#16*8]
	ldp	$A[3][3],$A[3][4],[$C[0],#16*9]
	ldp	$A[4][0],$A[4][1],[$C[0],#16*10]
	ldp	$A[4][2],$A[4][3],[$C[0],#16*11]
	ldr	$A[4][4],[$C[0],#16*12]
	b	.Loop_absorb

.align	4
.Loop_absorb:
	subs	$C[0],$C[2],$C[3]		// len - bsz
	blo	.Labsorbed

	str	$C[0],[sp,#48]			// save len - bsz
	ldr	$C[0],[$C[1]],#8		// *inp++
#ifdef	__AARCH64EB__
	rev	$C[0],$C[0]
#endif
	eor	$A[0][0],$A[0][0],$C[0]
	cmp	$C[3],#8*2
	blo	.Lprocess_block
	ldr	$C[0],[$C[1]],#8		// *inp++
#ifdef	__AARCH64EB__
	rev	$C[0],$C[0]
#endif
	eor	$A[0][1],$A[0][1],$C[0]
	beq	.Lprocess_block
	ldr	$C[0],[$C[1]],#8		// *inp++
#ifdef	__AARCH64EB__
	rev	$C[0],$C[0]
#endif
	eor	$A[0][2],$A[0][2],$C[0]
	cmp	$C[3],#8*4
	blo	.Lprocess_block
	ldr	$C[0],[$C[1]],#8		// *inp++
#ifdef	__AARCH64EB__
	rev	$C[0],$C[0]
#endif
	eor	$A[0][3],$A[0][3],$C[0]
	beq	.Lprocess_block
	ldr	$C[0],[$C[1]],#8		// *inp++
#ifdef	__AARCH64EB__
	rev	$C[0],$C[0]
#endif
	eor	$A[0][4],$A[0][4],$C[0]
	cmp	$C[3],#8*6
	blo	.Lprocess_block
	ldr	$C[0],[$C[1]],#8		// *inp++
#ifdef	__AARCH64EB__
	rev	$C[0],$C[0]
#endif
	eor	$A[1][0],$A[1][0],$C[0]
	beq	.Lprocess_block
	ldr	$C[0],[$C[1]],#8		// *inp++
#ifdef	__AARCH64EB__
	rev	$C[0],$C[0]
#endif
	eor	$A[1][1],$A[1][1],$C[0]
	cmp	$C[3],#8*8
	blo	.Lprocess_block
	ldr	$C[0],[$C[1]],#8		// *inp++
#ifdef	__AARCH64EB__
	rev	$C[0],$C[0]
#endif
	eor	$A[1][2],$A[1][2],$C[0]
	beq	.Lprocess_block
	ldr	$C[0],[$C[1]],#8		// *inp++
#ifdef	__AARCH64EB__
	rev	$C[0],$C[0]
#endif
	eor	$A[1][3],$A[1][3],$C[0]
	cmp	$C[3],#8*10
	blo	.Lprocess_block
	ldr	$C[0],[$C[1]],#8		// *inp++
#ifdef	__AARCH64EB__
	rev	$C[0],$C[0]
#endif
	eor	$A[1][4],$A[1][4],$C[0]
	beq	.Lprocess_block
	ldr	$C[0],[$C[1]],#8		// *inp++
#ifdef	__AARCH64EB__
	rev	$C[0],$C[0]
#endif
	eor	$A[2][0],$A[2][0],$C[0]
	cmp	$C[3],#8*12
	blo	.Lprocess_block
	ldr	$C[0],[$C[1]],#8		// *inp++
#ifdef	__AARCH64EB__
	rev	$C[0],$C[0]
#endif
	eor	$A[2][1],$A[2][1],$C[0]
	beq	.Lprocess_block
	ldr	$C[0],[$C[1]],#8		// *inp++
#ifdef	__AARCH64EB__
	rev	$C[0],$C[0]
#endif
	eor	$A[2][2],$A[2][2],$C[0]
	cmp	$C[3],#8*14
	blo	.Lprocess_block
	ldr	$C[0],[$C[1]],#8		// *inp++
#ifdef	__AARCH64EB__
	rev	$C[0],$C[0]
#endif
	eor	$A[2][3],$A[2][3],$C[0]
	beq	.Lprocess_block
	ldr	$C[0],[$C[1]],#8		// *inp++
#ifdef	__AARCH64EB__
	rev	$C[0],$C[0]
#endif
	eor	$A[2][4],$A[2][4],$C[0]
	cmp	$C[3],#8*16
	blo	.Lprocess_block
	ldr	$C[0],[$C[1]],#8		// *inp++
#ifdef	__AARCH64EB__
	rev	$C[0],$C[0]
#endif
	eor	$A[3][0],$A[3][0],$C[0]
	beq	.Lprocess_block
	ldr	$C[0],[$C[1]],#8		// *inp++
#ifdef	__AARCH64EB__
	rev	$C[0],$C[0]
#endif
	eor	$A[3][1],$A[3][1],$C[0]
	cmp	$C[3],#8*18
	blo	.Lprocess_block
	ldr	$C[0],[$C[1]],#8		// *inp++
#ifdef	__AARCH64EB__
	rev	$C[0],$C[0]
#endif
	eor	$A[3][2],$A[3][2],$C[0]
	beq	.Lprocess_block
	ldr	$C[0],[$C[1]],#8		// *inp++
#ifdef	__AARCH64EB__
	rev	$C[0],$C[0]
#endif
	eor	$A[3][3],$A[3][3],$C[0]
	cmp	$C[3],#8*20
	blo	.Lprocess_block
	ldr	$C[0],[$C[1]],#8		// *inp++
#ifdef	__AARCH64EB__
	rev	$C[0],$C[0]
#endif
	eor	$A[3][4],$A[3][4],$C[0]
	beq	.Lprocess_block
	ldr	$C[0],[$C[1]],#8		// *inp++
#ifdef	__AARCH64EB__
	rev	$C[0],$C[0]
#endif
	eor	$A[4][0],$A[4][0],$C[0]
	cmp	$C[3],#8*22
	blo	.Lprocess_block
	ldr	$C[0],[$C[1]],#8		// *inp++
#ifdef	__AARCH64EB__
	rev	$C[0],$C[0]
#endif
	eor	$A[4][1],$A[4][1],$C[0]
	beq	.Lprocess_block
	ldr	$C[0],[$C[1]],#8		// *inp++
#ifdef	__AARCH64EB__
	rev	$C[0],$C[0]
#endif
	eor	$A[4][2],$A[4][2],$C[0]
	cmp	$C[3],#8*24
	blo	.Lprocess_block
	ldr	$C[0],[$C[1]],#8		// *inp++
#ifdef	__AARCH64EB__
	rev	$C[0],$C[0]
#endif
	eor	$A[4][3],$A[4][3],$C[0]
	beq	.Lprocess_block
	ldr	$C[0],[$C[1]],#8		// *inp++
#ifdef	__AARCH64EB__
	rev	$C[0],$C[0]
#endif
	eor	$A[4][4],$A[4][4],$C[0]

.Lprocess_block:
	str	$C[1],[sp,#40]			// save inp

	bl	KeccakF1600_int

	ldr	$C[1],[sp,#40]			// restore arguments
	ldp	$C[2],$C[3],[sp,#48]
	b	.Loop_absorb

.align	4
.Labsorbed:
	ldr	$C[1],[sp,#32]
	stp	$A[0][0],$A[0][1],[$C[1],#16*0]
	stp	$A[0][2],$A[0][3],[$C[1],#16*1]
	stp	$A[0][4],$A[1][0],[$C[1],#16*2]
	stp	$A[1][1],$A[1][2],[$C[1],#16*3]
	stp	$A[1][3],$A[1][4],[$C[1],#16*4]
	stp	$A[2][0],$A[2][1],[$C[1],#16*5]
	stp	$A[2][2],$A[2][3],[$C[1],#16*6]
	stp	$A[2][4],$A[3][0],[$C[1],#16*7]
	stp	$A[3][1],$A[3][2],[$C[1],#16*8]
	stp	$A[3][3],$A[3][4],[$C[1],#16*9]
	stp	$A[4][0],$A[4][1],[$C[1],#16*10]
	stp	$A[4][2],$A[4][3],[$C[1],#16*11]
	str	$A[4][4],[$C[1],#16*12]

	mov	x0,$C[0]			// return value
	ldp	x19,x20,[x29,#16]
	add	sp,sp,#64
	ldp	x21,x22,[x29,#32]
	ldp	x23,x24,[x29,#48]
	ldp	x25,x26,[x29,#64]
	ldp	x27,x28,[x29,#80]
	ldp	x29,x30,[sp],#128
	ret
.size	SHA3_absorb,.-SHA3_absorb
___
{
my ($A_flat,$out,$len,$bsz) = map("x$_",(19..22));
$code.=<<___;
.globl	SHA3_squeeze
.type	SHA3_squeeze,%function
.align	5
SHA3_squeeze:
	stp	x29,x30,[sp,#-48]!
	add	x29,sp,#0
	stp	x19,x20,[sp,#16]
	stp	x21,x22,[sp,#32]

	mov	$A_flat,x0			// put aside arguments
	mov	$out,x1
	mov	$len,x2
	mov	$bsz,x3

.Loop_squeeze:
	ldr	x4,[x0],#8
	cmp	$len,#8
	blo	.Lsqueeze_tail
#ifdef	__AARCH64EB__
	rev	x4,x4
#endif
	str	x4,[$out],#8
	subs	$len,$len,#8
	beq	.Lsqueeze_done

	subs	x3,x3,#8
	bhi	.Loop_squeeze

	mov	x0,$A_flat
	bl	KeccakF1600
	mov	x0,$A_flat
	mov	x3,$bsz
	b	.Loop_squeeze

.align	4
.Lsqueeze_tail:
	strb	w4,[$out],#1
	lsr	x4,x4,#8
	subs	$len,$len,#1
	beq	.Lsqueeze_done
	strb	w4,[$out],#1
	lsr	x4,x4,#8
	subs	$len,$len,#1
	beq	.Lsqueeze_done
	strb	w4,[$out],#1
	lsr	x4,x4,#8
	subs	$len,$len,#1
	beq	.Lsqueeze_done
	strb	w4,[$out],#1
	lsr	x4,x4,#8
	subs	$len,$len,#1
	beq	.Lsqueeze_done
	strb	w4,[$out],#1
	lsr	x4,x4,#8
	subs	$len,$len,#1
	beq	.Lsqueeze_done
	strb	w4,[$out],#1
	lsr	x4,x4,#8
	subs	$len,$len,#1
	beq	.Lsqueeze_done
	strb	w4,[$out],#1

.Lsqueeze_done:
	ldp	x19,x20,[sp,#16]
	ldp	x21,x22,[sp,#32]
	ldp	x29,x30,[sp],#48
	ret
.size	SHA3_squeeze,.-SHA3_squeeze
.asciz	"Keccak-1600 absorb and squeeze for ARMv8, CRYPTOGAMS by <appro\@openssl.org>"
___
}

print $code;
close STDOUT;
