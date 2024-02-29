// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

contract Halo2Verifier {
    uint256 internal constant    PROOF_LEN_CPTR = 0x64;
    uint256 internal constant        PROOF_CPTR = 0x84;
    uint256 internal constant NUM_INSTANCE_CPTR = 0x1204;
    uint256 internal constant     INSTANCE_CPTR = 0x1224;

    uint256 internal constant FIRST_QUOTIENT_X_CPTR = 0x0684;
    uint256 internal constant  LAST_QUOTIENT_X_CPTR = 0x0784;

    uint256 internal constant                VK_MPTR = 0x06c0;
    uint256 internal constant         VK_DIGEST_MPTR = 0x06c0;
    uint256 internal constant     NUM_INSTANCES_MPTR = 0x06e0;
    uint256 internal constant                 K_MPTR = 0x0700;
    uint256 internal constant             N_INV_MPTR = 0x0720;
    uint256 internal constant             OMEGA_MPTR = 0x0740;
    uint256 internal constant         OMEGA_INV_MPTR = 0x0760;
    uint256 internal constant    OMEGA_INV_TO_L_MPTR = 0x0780;
    uint256 internal constant   HAS_ACCUMULATOR_MPTR = 0x07a0;
    uint256 internal constant        ACC_OFFSET_MPTR = 0x07c0;
    uint256 internal constant     NUM_ACC_LIMBS_MPTR = 0x07e0;
    uint256 internal constant NUM_ACC_LIMB_BITS_MPTR = 0x0800;
    uint256 internal constant              G1_X_MPTR = 0x0820;
    uint256 internal constant              G1_Y_MPTR = 0x0840;
    uint256 internal constant            G2_X_1_MPTR = 0x0860;
    uint256 internal constant            G2_X_2_MPTR = 0x0880;
    uint256 internal constant            G2_Y_1_MPTR = 0x08a0;
    uint256 internal constant            G2_Y_2_MPTR = 0x08c0;
    uint256 internal constant      NEG_S_G2_X_1_MPTR = 0x08e0;
    uint256 internal constant      NEG_S_G2_X_2_MPTR = 0x0900;
    uint256 internal constant      NEG_S_G2_Y_1_MPTR = 0x0920;
    uint256 internal constant      NEG_S_G2_Y_2_MPTR = 0x0940;

    uint256 internal constant CHALLENGE_MPTR = 0x1160;

    uint256 internal constant THETA_MPTR = 0x1160;
    uint256 internal constant  BETA_MPTR = 0x1180;
    uint256 internal constant GAMMA_MPTR = 0x11a0;
    uint256 internal constant     Y_MPTR = 0x11c0;
    uint256 internal constant     X_MPTR = 0x11e0;
    uint256 internal constant  ZETA_MPTR = 0x1200;
    uint256 internal constant    NU_MPTR = 0x1220;
    uint256 internal constant    MU_MPTR = 0x1240;

    uint256 internal constant       ACC_LHS_X_MPTR = 0x1260;
    uint256 internal constant       ACC_LHS_Y_MPTR = 0x1280;
    uint256 internal constant       ACC_RHS_X_MPTR = 0x12a0;
    uint256 internal constant       ACC_RHS_Y_MPTR = 0x12c0;
    uint256 internal constant             X_N_MPTR = 0x12e0;
    uint256 internal constant X_N_MINUS_1_INV_MPTR = 0x1300;
    uint256 internal constant          L_LAST_MPTR = 0x1320;
    uint256 internal constant         L_BLIND_MPTR = 0x1340;
    uint256 internal constant             L_0_MPTR = 0x1360;
    uint256 internal constant   INSTANCE_EVAL_MPTR = 0x1380;
    uint256 internal constant   QUOTIENT_EVAL_MPTR = 0x13a0;
    uint256 internal constant      QUOTIENT_X_MPTR = 0x13c0;
    uint256 internal constant      QUOTIENT_Y_MPTR = 0x13e0;
    uint256 internal constant          R_EVAL_MPTR = 0x1400;
    uint256 internal constant   PAIRING_LHS_X_MPTR = 0x1420;
    uint256 internal constant   PAIRING_LHS_Y_MPTR = 0x1440;
    uint256 internal constant   PAIRING_RHS_X_MPTR = 0x1460;
    uint256 internal constant   PAIRING_RHS_Y_MPTR = 0x1480;

    function verifyProof(
        address vk,
        bytes calldata proof,
        uint256[] calldata instances
    ) public returns (bool) {
        assembly {
            // Read EC point (x, y) at (proof_cptr, proof_cptr + 0x20),
            // and check if the point is on affine plane,
            // and store them in (hash_mptr, hash_mptr + 0x20).
            // Return updated (success, proof_cptr, hash_mptr).
            function read_ec_point(success, proof_cptr, hash_mptr, q) -> ret0, ret1, ret2 {
                let x := calldataload(proof_cptr)
                let y := calldataload(add(proof_cptr, 0x20))
                ret0 := and(success, lt(x, q))
                ret0 := and(ret0, lt(y, q))
                ret0 := and(ret0, eq(mulmod(y, y, q), addmod(mulmod(x, mulmod(x, x, q), q), 3, q)))
                mstore(hash_mptr, x)
                mstore(add(hash_mptr, 0x20), y)
                ret1 := add(proof_cptr, 0x40)
                ret2 := add(hash_mptr, 0x40)
            }

            // Squeeze challenge by keccak256(memory[0..hash_mptr]),
            // and store hash mod r as challenge in challenge_mptr,
            // and push back hash in 0x00 as the first input for next squeeze.
            // Return updated (challenge_mptr, hash_mptr).
            function squeeze_challenge(challenge_mptr, hash_mptr, r) -> ret0, ret1 {
                let hash := keccak256(0x00, hash_mptr)
                mstore(challenge_mptr, mod(hash, r))
                mstore(0x00, hash)
                ret0 := add(challenge_mptr, 0x20)
                ret1 := 0x20
            }

            // Squeeze challenge without absorbing new input from calldata,
            // by putting an extra 0x01 in memory[0x20] and squeeze by keccak256(memory[0..21]),
            // and store hash mod r as challenge in challenge_mptr,
            // and push back hash in 0x00 as the first input for next squeeze.
            // Return updated (challenge_mptr).
            function squeeze_challenge_cont(challenge_mptr, r) -> ret {
                mstore8(0x20, 0x01)
                let hash := keccak256(0x00, 0x21)
                mstore(challenge_mptr, mod(hash, r))
                mstore(0x00, hash)
                ret := add(challenge_mptr, 0x20)
            }

            // Batch invert values in memory[mptr_start..mptr_end] in place.
            // Return updated (success).
            function batch_invert(success, mptr_start, mptr_end, r) -> ret {
                let gp_mptr := mptr_end
                let gp := mload(mptr_start)
                let mptr := add(mptr_start, 0x20)
                for
                    {}
                    lt(mptr, sub(mptr_end, 0x20))
                    {}
                {
                    gp := mulmod(gp, mload(mptr), r)
                    mstore(gp_mptr, gp)
                    mptr := add(mptr, 0x20)
                    gp_mptr := add(gp_mptr, 0x20)
                }
                gp := mulmod(gp, mload(mptr), r)

                mstore(gp_mptr, 0x20)
                mstore(add(gp_mptr, 0x20), 0x20)
                mstore(add(gp_mptr, 0x40), 0x20)
                mstore(add(gp_mptr, 0x60), gp)
                mstore(add(gp_mptr, 0x80), sub(r, 2))
                mstore(add(gp_mptr, 0xa0), r)
                ret := and(success, staticcall(gas(), 0x05, gp_mptr, 0xc0, gp_mptr, 0x20))
                let all_inv := mload(gp_mptr)

                let first_mptr := mptr_start
                let second_mptr := add(first_mptr, 0x20)
                gp_mptr := sub(gp_mptr, 0x20)
                for
                    {}
                    lt(second_mptr, mptr)
                    {}
                {
                    let inv := mulmod(all_inv, mload(gp_mptr), r)
                    all_inv := mulmod(all_inv, mload(mptr), r)
                    mstore(mptr, inv)
                    mptr := sub(mptr, 0x20)
                    gp_mptr := sub(gp_mptr, 0x20)
                }
                let inv_first := mulmod(all_inv, mload(second_mptr), r)
                let inv_second := mulmod(all_inv, mload(first_mptr), r)
                mstore(first_mptr, inv_first)
                mstore(second_mptr, inv_second)
            }

            // Add (x, y) into point at (0x00, 0x20).
            // Return updated (success).
            function ec_add_acc(success, x, y) -> ret {
                mstore(0x40, x)
                mstore(0x60, y)
                ret := and(success, staticcall(gas(), 0x06, 0x00, 0x80, 0x00, 0x40))
            }

            // Scale point at (0x00, 0x20) by scalar.
            function ec_mul_acc(success, scalar) -> ret {
                mstore(0x40, scalar)
                ret := and(success, staticcall(gas(), 0x07, 0x00, 0x60, 0x00, 0x40))
            }

            // Add (x, y) into point at (0x80, 0xa0).
            // Return updated (success).
            function ec_add_tmp(success, x, y) -> ret {
                mstore(0xc0, x)
                mstore(0xe0, y)
                ret := and(success, staticcall(gas(), 0x06, 0x80, 0x80, 0x80, 0x40))
            }

            // Scale point at (0x80, 0xa0) by scalar.
            // Return updated (success).
            function ec_mul_tmp(success, scalar) -> ret {
                mstore(0xc0, scalar)
                ret := and(success, staticcall(gas(), 0x07, 0x80, 0x60, 0x80, 0x40))
            }

            // Perform pairing check.
            // Return updated (success).
            function ec_pairing(success, lhs_x, lhs_y, rhs_x, rhs_y) -> ret {
                mstore(0x00, lhs_x)
                mstore(0x20, lhs_y)
                mstore(0x40, mload(G2_X_1_MPTR))
                mstore(0x60, mload(G2_X_2_MPTR))
                mstore(0x80, mload(G2_Y_1_MPTR))
                mstore(0xa0, mload(G2_Y_2_MPTR))
                mstore(0xc0, rhs_x)
                mstore(0xe0, rhs_y)
                mstore(0x100, mload(NEG_S_G2_X_1_MPTR))
                mstore(0x120, mload(NEG_S_G2_X_2_MPTR))
                mstore(0x140, mload(NEG_S_G2_Y_1_MPTR))
                mstore(0x160, mload(NEG_S_G2_Y_2_MPTR))
                ret := and(success, staticcall(gas(), 0x08, 0x00, 0x180, 0x00, 0x20))
                ret := and(ret, mload(0x00))
            }

            // Modulus
            let q := 21888242871839275222246405745257275088696311157297823662689037894645226208583 // BN254 base field
            let r := 21888242871839275222246405745257275088548364400416034343698204186575808495617 // BN254 scalar field

            // Initialize success as true
            let success := true

            {
                // Copy vk_digest and num_instances of vk into memory
                extcodecopy(vk, VK_MPTR, 0x00, 0x40)

                // Check valid length of proof
                success := and(success, eq(0x1180, calldataload(PROOF_LEN_CPTR)))

                // Check valid length of instances
                let num_instances := mload(NUM_INSTANCES_MPTR)
                success := and(success, eq(num_instances, calldataload(NUM_INSTANCE_CPTR)))

                // Absorb vk diegst
                mstore(0x00, mload(VK_DIGEST_MPTR))

                // Read instances and witness commitments and generate challenges
                let hash_mptr := 0x20
                let instance_cptr := INSTANCE_CPTR
                for
                    { let instance_cptr_end := add(instance_cptr, mul(0x20, num_instances)) }
                    lt(instance_cptr, instance_cptr_end)
                    {}
                {
                    let instance := calldataload(instance_cptr)
                    success := and(success, lt(instance, r))
                    mstore(hash_mptr, instance)
                    instance_cptr := add(instance_cptr, 0x20)
                    hash_mptr := add(hash_mptr, 0x20)
                }

                let proof_cptr := PROOF_CPTR
                let challenge_mptr := CHALLENGE_MPTR

                // Phase 1
                for
                    { let proof_cptr_end := add(proof_cptr, 0x0140) }
                    lt(proof_cptr, proof_cptr_end)
                    {}
                {
                    success, proof_cptr, hash_mptr := read_ec_point(success, proof_cptr, hash_mptr, q)
                }

                challenge_mptr, hash_mptr := squeeze_challenge(challenge_mptr, hash_mptr, r)

                // Phase 2
                for
                    { let proof_cptr_end := add(proof_cptr, 0x0280) }
                    lt(proof_cptr, proof_cptr_end)
                    {}
                {
                    success, proof_cptr, hash_mptr := read_ec_point(success, proof_cptr, hash_mptr, q)
                }

                challenge_mptr, hash_mptr := squeeze_challenge(challenge_mptr, hash_mptr, r)
                challenge_mptr := squeeze_challenge_cont(challenge_mptr, r)

                // Phase 3
                for
                    { let proof_cptr_end := add(proof_cptr, 0x0240) }
                    lt(proof_cptr, proof_cptr_end)
                    {}
                {
                    success, proof_cptr, hash_mptr := read_ec_point(success, proof_cptr, hash_mptr, q)
                }

                challenge_mptr, hash_mptr := squeeze_challenge(challenge_mptr, hash_mptr, r)

                // Phase 4
                for
                    { let proof_cptr_end := add(proof_cptr, 0x0140) }
                    lt(proof_cptr, proof_cptr_end)
                    {}
                {
                    success, proof_cptr, hash_mptr := read_ec_point(success, proof_cptr, hash_mptr, q)
                }

                challenge_mptr, hash_mptr := squeeze_challenge(challenge_mptr, hash_mptr, r)

                // Read evaluations
                for
                    { let proof_cptr_end := add(proof_cptr, 0x09c0) }
                    lt(proof_cptr, proof_cptr_end)
                    {}
                {
                    let eval := calldataload(proof_cptr)
                    success := and(success, lt(eval, r))
                    mstore(hash_mptr, eval)
                    proof_cptr := add(proof_cptr, 0x20)
                    hash_mptr := add(hash_mptr, 0x20)
                }

                // Read batch opening proof and generate challenges
                challenge_mptr, hash_mptr := squeeze_challenge(challenge_mptr, hash_mptr, r)       // zeta
                challenge_mptr := squeeze_challenge_cont(challenge_mptr, r)                        // nu

                success, proof_cptr, hash_mptr := read_ec_point(success, proof_cptr, hash_mptr, q) // W

                challenge_mptr, hash_mptr := squeeze_challenge(challenge_mptr, hash_mptr, r)       // mu

                success, proof_cptr, hash_mptr := read_ec_point(success, proof_cptr, hash_mptr, q) // W'

                // Copy full vk into memory
                extcodecopy(vk, VK_MPTR, 0x00, 0x0aa0)

                // Read accumulator from instances
                if mload(HAS_ACCUMULATOR_MPTR) {
                    let num_limbs := mload(NUM_ACC_LIMBS_MPTR)
                    let num_limb_bits := mload(NUM_ACC_LIMB_BITS_MPTR)

                    let cptr := add(INSTANCE_CPTR, mul(mload(ACC_OFFSET_MPTR), 0x20))
                    let lhs_y_off := mul(num_limbs, 0x20)
                    let rhs_x_off := mul(lhs_y_off, 2)
                    let rhs_y_off := mul(lhs_y_off, 3)
                    let lhs_x := calldataload(cptr)
                    let lhs_y := calldataload(add(cptr, lhs_y_off))
                    let rhs_x := calldataload(add(cptr, rhs_x_off))
                    let rhs_y := calldataload(add(cptr, rhs_y_off))
                    for
                        {
                            let cptr_end := add(cptr, mul(0x20, num_limbs))
                            let shift := num_limb_bits
                        }
                        lt(cptr, cptr_end)
                        {}
                    {
                        cptr := add(cptr, 0x20)
                        lhs_x := add(lhs_x, shl(shift, calldataload(cptr)))
                        lhs_y := add(lhs_y, shl(shift, calldataload(add(cptr, lhs_y_off))))
                        rhs_x := add(rhs_x, shl(shift, calldataload(add(cptr, rhs_x_off))))
                        rhs_y := add(rhs_y, shl(shift, calldataload(add(cptr, rhs_y_off))))
                        shift := add(shift, num_limb_bits)
                    }

                    success := and(success, eq(mulmod(lhs_y, lhs_y, q), addmod(mulmod(lhs_x, mulmod(lhs_x, lhs_x, q), q), 3, q)))
                    success := and(success, eq(mulmod(rhs_y, rhs_y, q), addmod(mulmod(rhs_x, mulmod(rhs_x, rhs_x, q), q), 3, q)))

                    mstore(ACC_LHS_X_MPTR, lhs_x)
                    mstore(ACC_LHS_Y_MPTR, lhs_y)
                    mstore(ACC_RHS_X_MPTR, rhs_x)
                    mstore(ACC_RHS_Y_MPTR, rhs_y)
                }

                pop(q)
            }

            // Revert earlier if anything from calldata is invalid
            if iszero(success) {
                revert(0, 0)
            }

            // Compute lagrange evaluations and instance evaluation
            {
                let k := mload(K_MPTR)
                let x := mload(X_MPTR)
                let x_n := x
                for
                    { let idx := 0 }
                    lt(idx, k)
                    { idx := add(idx, 1) }
                {
                    x_n := mulmod(x_n, x_n, r)
                }

                let omega := mload(OMEGA_MPTR)

                let mptr := X_N_MPTR
                let mptr_end := add(mptr, mul(0x20, add(mload(NUM_INSTANCES_MPTR), 6)))
                if iszero(mload(NUM_INSTANCES_MPTR)) {
                    mptr_end := add(mptr_end, 0x20)
                }
                for
                    { let pow_of_omega := mload(OMEGA_INV_TO_L_MPTR) }
                    lt(mptr, mptr_end)
                    { mptr := add(mptr, 0x20) }
                {
                    mstore(mptr, addmod(x, sub(r, pow_of_omega), r))
                    pow_of_omega := mulmod(pow_of_omega, omega, r)
                }
                let x_n_minus_1 := addmod(x_n, sub(r, 1), r)
                mstore(mptr_end, x_n_minus_1)
                success := batch_invert(success, X_N_MPTR, add(mptr_end, 0x20), r)

                mptr := X_N_MPTR
                let l_i_common := mulmod(x_n_minus_1, mload(N_INV_MPTR), r)
                for
                    { let pow_of_omega := mload(OMEGA_INV_TO_L_MPTR) }
                    lt(mptr, mptr_end)
                    { mptr := add(mptr, 0x20) }
                {
                    mstore(mptr, mulmod(l_i_common, mulmod(mload(mptr), pow_of_omega, r), r))
                    pow_of_omega := mulmod(pow_of_omega, omega, r)
                }

                let l_blind := mload(add(X_N_MPTR, 0x20))
                let l_i_cptr := add(X_N_MPTR, 0x40)
                for
                    { let l_i_cptr_end := add(X_N_MPTR, 0xc0) }
                    lt(l_i_cptr, l_i_cptr_end)
                    { l_i_cptr := add(l_i_cptr, 0x20) }
                {
                    l_blind := addmod(l_blind, mload(l_i_cptr), r)
                }

                let instance_eval := 0
                for
                    {
                        let instance_cptr := INSTANCE_CPTR
                        let instance_cptr_end := add(instance_cptr, mul(0x20, mload(NUM_INSTANCES_MPTR)))
                    }
                    lt(instance_cptr, instance_cptr_end)
                    {
                        instance_cptr := add(instance_cptr, 0x20)
                        l_i_cptr := add(l_i_cptr, 0x20)
                    }
                {
                    instance_eval := addmod(instance_eval, mulmod(mload(l_i_cptr), calldataload(instance_cptr), r), r)
                }

                let x_n_minus_1_inv := mload(mptr_end)
                let l_last := mload(X_N_MPTR)
                let l_0 := mload(add(X_N_MPTR, 0xc0))

                mstore(X_N_MPTR, x_n)
                mstore(X_N_MINUS_1_INV_MPTR, x_n_minus_1_inv)
                mstore(L_LAST_MPTR, l_last)
                mstore(L_BLIND_MPTR, l_blind)
                mstore(L_0_MPTR, l_0)
                mstore(INSTANCE_EVAL_MPTR, instance_eval)
            }

            // Compute quotient evavluation
            {
                let quotient_eval_numer
                let delta := 4131629893567559867359510883348571134090853742863529169391034518566172092834
                let y := mload(Y_MPTR)
                {
                    let a_0 := calldataload(0x07c4)
                    let f_0 := calldataload(0x0944)
                    let var0 := mulmod(a_0, f_0, r)
                    let a_1 := calldataload(0x07e4)
                    let f_1 := calldataload(0x0964)
                    let var1 := mulmod(a_1, f_1, r)
                    let var2 := addmod(var0, var1, r)
                    let a_2 := calldataload(0x0804)
                    let f_2 := calldataload(0x0984)
                    let var3 := mulmod(a_2, f_2, r)
                    let var4 := addmod(var2, var3, r)
                    let a_3 := calldataload(0x0824)
                    let f_3 := calldataload(0x09a4)
                    let var5 := mulmod(a_3, f_3, r)
                    let var6 := addmod(var4, var5, r)
                    let a_4 := calldataload(0x0844)
                    let f_4 := calldataload(0x09c4)
                    let var7 := mulmod(a_4, f_4, r)
                    let var8 := addmod(var6, var7, r)
                    let var9 := mulmod(a_0, a_1, r)
                    let f_5 := calldataload(0x0a04)
                    let var10 := mulmod(var9, f_5, r)
                    let var11 := addmod(var8, var10, r)
                    let var12 := mulmod(a_2, a_3, r)
                    let f_6 := calldataload(0x0a24)
                    let var13 := mulmod(var12, f_6, r)
                    let var14 := addmod(var11, var13, r)
                    let f_7 := calldataload(0x09e4)
                    let a_4_next_1 := calldataload(0x0864)
                    let var15 := mulmod(f_7, a_4_next_1, r)
                    let var16 := addmod(var14, var15, r)
                    let f_8 := calldataload(0x0a44)
                    let var17 := addmod(var16, f_8, r)
                    quotient_eval_numer := var17
                }
                {
                    let f_20 := calldataload(0x0bc4)
                    let a_0 := calldataload(0x07c4)
                    let f_12 := calldataload(0x0b24)
                    let var0 := addmod(a_0, f_12, r)
                    let var1 := mulmod(var0, var0, r)
                    let var2 := mulmod(var1, var1, r)
                    let var3 := mulmod(var2, var0, r)
                    let var4 := mulmod(var3, 0x109b7f411ba0e4c9b2b70caf5c36a7b194be7c11ad24378bfedb68592ba8118b, r)
                    let a_1 := calldataload(0x07e4)
                    let f_13 := calldataload(0x0b44)
                    let var5 := addmod(a_1, f_13, r)
                    let var6 := mulmod(var5, var5, r)
                    let var7 := mulmod(var6, var6, r)
                    let var8 := mulmod(var7, var5, r)
                    let var9 := mulmod(var8, 0x16ed41e13bb9c0c66ae119424fddbcbc9314dc9fdbdeea55d6c64543dc4903e0, r)
                    let var10 := addmod(var4, var9, r)
                    let a_2 := calldataload(0x0804)
                    let f_14 := calldataload(0x0b64)
                    let var11 := addmod(a_2, f_14, r)
                    let var12 := mulmod(var11, var11, r)
                    let var13 := mulmod(var12, var12, r)
                    let var14 := mulmod(var13, var11, r)
                    let var15 := mulmod(var14, 0x2b90bba00fca0589f617e7dcbfe82e0df706ab640ceb247b791a93b74e36736d, r)
                    let var16 := addmod(var10, var15, r)
                    let a_0_next_1 := calldataload(0x0884)
                    let var17 := sub(r, a_0_next_1)
                    let var18 := addmod(var16, var17, r)
                    let var19 := mulmod(f_20, var18, r)
                    quotient_eval_numer := addmod(mulmod(quotient_eval_numer, y, r), var19, r)
                }
                {
                    let f_20 := calldataload(0x0bc4)
                    let a_0 := calldataload(0x07c4)
                    let f_12 := calldataload(0x0b24)
                    let var0 := addmod(a_0, f_12, r)
                    let var1 := mulmod(var0, var0, r)
                    let var2 := mulmod(var1, var1, r)
                    let var3 := mulmod(var2, var0, r)
                    let var4 := mulmod(var3, 0x2969f27eed31a480b9c36c764379dbca2cc8fdd1415c3dded62940bcde0bd771, r)
                    let a_1 := calldataload(0x07e4)
                    let f_13 := calldataload(0x0b44)
                    let var5 := addmod(a_1, f_13, r)
                    let var6 := mulmod(var5, var5, r)
                    let var7 := mulmod(var6, var6, r)
                    let var8 := mulmod(var7, var5, r)
                    let var9 := mulmod(var8, 0x2e2419f9ec02ec394c9871c832963dc1b89d743c8c7b964029b2311687b1fe23, r)
                    let var10 := addmod(var4, var9, r)
                    let a_2 := calldataload(0x0804)
                    let f_14 := calldataload(0x0b64)
                    let var11 := addmod(a_2, f_14, r)
                    let var12 := mulmod(var11, var11, r)
                    let var13 := mulmod(var12, var12, r)
                    let var14 := mulmod(var13, var11, r)
                    let var15 := mulmod(var14, 0x101071f0032379b697315876690f053d148d4e109f5fb065c8aacc55a0f89bfa, r)
                    let var16 := addmod(var10, var15, r)
                    let a_1_next_1 := calldataload(0x08a4)
                    let var17 := sub(r, a_1_next_1)
                    let var18 := addmod(var16, var17, r)
                    let var19 := mulmod(f_20, var18, r)
                    quotient_eval_numer := addmod(mulmod(quotient_eval_numer, y, r), var19, r)
                }
                {
                    let f_20 := calldataload(0x0bc4)
                    let a_0 := calldataload(0x07c4)
                    let f_12 := calldataload(0x0b24)
                    let var0 := addmod(a_0, f_12, r)
                    let var1 := mulmod(var0, var0, r)
                    let var2 := mulmod(var1, var1, r)
                    let var3 := mulmod(var2, var0, r)
                    let var4 := mulmod(var3, 0x143021ec686a3f330d5f9e654638065ce6cd79e28c5b3753326244ee65a1b1a7, r)
                    let a_1 := calldataload(0x07e4)
                    let f_13 := calldataload(0x0b44)
                    let var5 := addmod(a_1, f_13, r)
                    let var6 := mulmod(var5, var5, r)
                    let var7 := mulmod(var6, var6, r)
                    let var8 := mulmod(var7, var5, r)
                    let var9 := mulmod(var8, 0x176cc029695ad02582a70eff08a6fd99d057e12e58e7d7b6b16cdfabc8ee2911, r)
                    let var10 := addmod(var4, var9, r)
                    let a_2 := calldataload(0x0804)
                    let f_14 := calldataload(0x0b64)
                    let var11 := addmod(a_2, f_14, r)
                    let var12 := mulmod(var11, var11, r)
                    let var13 := mulmod(var12, var12, r)
                    let var14 := mulmod(var13, var11, r)
                    let var15 := mulmod(var14, 0x19a3fc0a56702bf417ba7fee3802593fa644470307043f7773279cd71d25d5e0, r)
                    let var16 := addmod(var10, var15, r)
                    let a_2_next_1 := calldataload(0x08c4)
                    let var17 := sub(r, a_2_next_1)
                    let var18 := addmod(var16, var17, r)
                    let var19 := mulmod(f_20, var18, r)
                    quotient_eval_numer := addmod(mulmod(quotient_eval_numer, y, r), var19, r)
                }
                {
                    let f_21 := calldataload(0x0be4)
                    let a_0 := calldataload(0x07c4)
                    let f_12 := calldataload(0x0b24)
                    let var0 := addmod(a_0, f_12, r)
                    let var1 := mulmod(var0, var0, r)
                    let var2 := mulmod(var1, var1, r)
                    let var3 := mulmod(var2, var0, r)
                    let a_3 := calldataload(0x0824)
                    let var4 := sub(r, a_3)
                    let var5 := addmod(var3, var4, r)
                    let var6 := mulmod(f_21, var5, r)
                    quotient_eval_numer := addmod(mulmod(quotient_eval_numer, y, r), var6, r)
                }
                {
                    let f_21 := calldataload(0x0be4)
                    let a_3 := calldataload(0x0824)
                    let var0 := mulmod(a_3, 0x109b7f411ba0e4c9b2b70caf5c36a7b194be7c11ad24378bfedb68592ba8118b, r)
                    let a_1 := calldataload(0x07e4)
                    let f_13 := calldataload(0x0b44)
                    let var1 := addmod(a_1, f_13, r)
                    let var2 := mulmod(var1, 0x16ed41e13bb9c0c66ae119424fddbcbc9314dc9fdbdeea55d6c64543dc4903e0, r)
                    let var3 := addmod(var0, var2, r)
                    let a_2 := calldataload(0x0804)
                    let f_14 := calldataload(0x0b64)
                    let var4 := addmod(a_2, f_14, r)
                    let var5 := mulmod(var4, 0x2b90bba00fca0589f617e7dcbfe82e0df706ab640ceb247b791a93b74e36736d, r)
                    let var6 := addmod(var3, var5, r)
                    let f_15 := calldataload(0x0ac4)
                    let var7 := addmod(var6, f_15, r)
                    let var8 := mulmod(var7, var7, r)
                    let var9 := mulmod(var8, var8, r)
                    let var10 := mulmod(var9, var7, r)
                    let a_0_next_1 := calldataload(0x0884)
                    let var11 := mulmod(a_0_next_1, 0x203d1d351372bf15b6465d69d3e12806879a5f36b4ba6dd17dfea07d03f82f26, r)
                    let a_1_next_1 := calldataload(0x08a4)
                    let var12 := mulmod(a_1_next_1, 0x29b6537218615bcb4b6ad7fe4620063d48e42ce2096b3a1d6e320628bb032c22, r)
                    let var13 := addmod(var11, var12, r)
                    let a_2_next_1 := calldataload(0x08c4)
                    let var14 := mulmod(a_2_next_1, 0x11551257de3d4b5ab51bd377d7bb55c054f51f711623515b1e2a35a958b93a6a, r)
                    let var15 := addmod(var13, var14, r)
                    let var16 := sub(r, var15)
                    let var17 := addmod(var10, var16, r)
                    let var18 := mulmod(f_21, var17, r)
                    quotient_eval_numer := addmod(mulmod(quotient_eval_numer, y, r), var18, r)
                }
                {
                    let f_21 := calldataload(0x0be4)
                    let a_3 := calldataload(0x0824)
                    let var0 := mulmod(a_3, 0x2969f27eed31a480b9c36c764379dbca2cc8fdd1415c3dded62940bcde0bd771, r)
                    let a_1 := calldataload(0x07e4)
                    let f_13 := calldataload(0x0b44)
                    let var1 := addmod(a_1, f_13, r)
                    let var2 := mulmod(var1, 0x2e2419f9ec02ec394c9871c832963dc1b89d743c8c7b964029b2311687b1fe23, r)
                    let var3 := addmod(var0, var2, r)
                    let a_2 := calldataload(0x0804)
                    let f_14 := calldataload(0x0b64)
                    let var4 := addmod(a_2, f_14, r)
                    let var5 := mulmod(var4, 0x101071f0032379b697315876690f053d148d4e109f5fb065c8aacc55a0f89bfa, r)
                    let var6 := addmod(var3, var5, r)
                    let f_16 := calldataload(0x0ae4)
                    let var7 := addmod(var6, f_16, r)
                    let a_0_next_1 := calldataload(0x0884)
                    let var8 := mulmod(a_0_next_1, 0x29dedb1bbf80c8863d569912c20f1f82bf0dc3bc4fb62798dd1319814f833b54, r)
                    let a_1_next_1 := calldataload(0x08a4)
                    let var9 := mulmod(a_1_next_1, 0x130b59143f4e340cd66c7251dc8f56fbbe0367fec1575cb124ca8a66304e3849, r)
                    let var10 := addmod(var8, var9, r)
                    let a_2_next_1 := calldataload(0x08c4)
                    let var11 := mulmod(a_2_next_1, 0x0c2808c9533e2c526087842fb62521a3248c8d6d3b16d4b4108476d2eeda95f9, r)
                    let var12 := addmod(var10, var11, r)
                    let var13 := sub(r, var12)
                    let var14 := addmod(var7, var13, r)
                    let var15 := mulmod(f_21, var14, r)
                    quotient_eval_numer := addmod(mulmod(quotient_eval_numer, y, r), var15, r)
                }
                {
                    let f_21 := calldataload(0x0be4)
                    let a_3 := calldataload(0x0824)
                    let var0 := mulmod(a_3, 0x143021ec686a3f330d5f9e654638065ce6cd79e28c5b3753326244ee65a1b1a7, r)
                    let a_1 := calldataload(0x07e4)
                    let f_13 := calldataload(0x0b44)
                    let var1 := addmod(a_1, f_13, r)
                    let var2 := mulmod(var1, 0x176cc029695ad02582a70eff08a6fd99d057e12e58e7d7b6b16cdfabc8ee2911, r)
                    let var3 := addmod(var0, var2, r)
                    let a_2 := calldataload(0x0804)
                    let f_14 := calldataload(0x0b64)
                    let var4 := addmod(a_2, f_14, r)
                    let var5 := mulmod(var4, 0x19a3fc0a56702bf417ba7fee3802593fa644470307043f7773279cd71d25d5e0, r)
                    let var6 := addmod(var3, var5, r)
                    let f_17 := calldataload(0x0b04)
                    let var7 := addmod(var6, f_17, r)
                    let a_0_next_1 := calldataload(0x0884)
                    let var8 := mulmod(a_0_next_1, 0x0173249a1c9eac2591706fe09af22cfd29e1387e706cf0ded2889dc145c61609, r)
                    let a_1_next_1 := calldataload(0x08a4)
                    let var9 := mulmod(a_1_next_1, 0x0abc7f158780841ec82e03ec3cee0cf1d16270b0238f3063d2e5fb5138e59350, r)
                    let var10 := addmod(var8, var9, r)
                    let a_2_next_1 := calldataload(0x08c4)
                    let var11 := mulmod(a_2_next_1, 0x1738a318c8631b6e8305505aaf3b497fe9f2478c2f28ee945413af26963b4700, r)
                    let var12 := addmod(var10, var11, r)
                    let var13 := sub(r, var12)
                    let var14 := addmod(var7, var13, r)
                    let var15 := mulmod(f_21, var14, r)
                    quotient_eval_numer := addmod(mulmod(quotient_eval_numer, y, r), var15, r)
                }
                {
                    let f_22 := calldataload(0x0c04)
                    let a_0_prev_1 := calldataload(0x0904)
                    let a_0 := calldataload(0x07c4)
                    let var0 := addmod(a_0_prev_1, a_0, r)
                    let a_0_next_1 := calldataload(0x0884)
                    let var1 := sub(r, a_0_next_1)
                    let var2 := addmod(var0, var1, r)
                    let var3 := mulmod(f_22, var2, r)
                    quotient_eval_numer := addmod(mulmod(quotient_eval_numer, y, r), var3, r)
                }
                {
                    let f_22 := calldataload(0x0c04)
                    let a_1_prev_1 := calldataload(0x0924)
                    let a_1 := calldataload(0x07e4)
                    let var0 := addmod(a_1_prev_1, a_1, r)
                    let a_1_next_1 := calldataload(0x08a4)
                    let var1 := sub(r, a_1_next_1)
                    let var2 := addmod(var0, var1, r)
                    let var3 := mulmod(f_22, var2, r)
                    quotient_eval_numer := addmod(mulmod(quotient_eval_numer, y, r), var3, r)
                }
                {
                    let f_22 := calldataload(0x0c04)
                    let a_2_prev_1 := calldataload(0x08e4)
                    let a_2_next_1 := calldataload(0x08c4)
                    let var0 := sub(r, a_2_next_1)
                    let var1 := addmod(a_2_prev_1, var0, r)
                    let var2 := mulmod(f_22, var1, r)
                    quotient_eval_numer := addmod(mulmod(quotient_eval_numer, y, r), var2, r)
                }
                {
                    let l_0 := mload(L_0_MPTR)
                    let eval := addmod(l_0, sub(r, mulmod(l_0, calldataload(0x0d64), r)), r)
                    quotient_eval_numer := addmod(mulmod(quotient_eval_numer, y, r), eval, r)
                }
                {
                    let perm_z_last := calldataload(0x0e24)
                    let eval := mulmod(mload(L_LAST_MPTR), addmod(mulmod(perm_z_last, perm_z_last, r), sub(r, perm_z_last), r), r)
                    quotient_eval_numer := addmod(mulmod(quotient_eval_numer, y, r), eval, r)
                }
                {
                    let eval := mulmod(mload(L_0_MPTR), addmod(calldataload(0x0dc4), sub(r, calldataload(0x0da4)), r), r)
                    quotient_eval_numer := addmod(mulmod(quotient_eval_numer, y, r), eval, r)
                }
                {
                    let eval := mulmod(mload(L_0_MPTR), addmod(calldataload(0x0e24), sub(r, calldataload(0x0e04)), r), r)
                    quotient_eval_numer := addmod(mulmod(quotient_eval_numer, y, r), eval, r)
                }
                {
                    let gamma := mload(GAMMA_MPTR)
                    let beta := mload(BETA_MPTR)
                    let lhs := calldataload(0x0d84)
                    let rhs := calldataload(0x0d64)
                    lhs := mulmod(lhs, addmod(addmod(calldataload(0x07c4), mulmod(beta, calldataload(0x0c44), r), r), gamma, r), r)
                    lhs := mulmod(lhs, addmod(addmod(calldataload(0x07e4), mulmod(beta, calldataload(0x0c64), r), r), gamma, r), r)
                    lhs := mulmod(lhs, addmod(addmod(calldataload(0x0804), mulmod(beta, calldataload(0x0c84), r), r), gamma, r), r)
                    lhs := mulmod(lhs, addmod(addmod(calldataload(0x0824), mulmod(beta, calldataload(0x0ca4), r), r), gamma, r), r)
                    mstore(0x00, mulmod(beta, mload(X_MPTR), r))
                    rhs := mulmod(rhs, addmod(addmod(calldataload(0x07c4), mload(0x00), r), gamma, r), r)
                    mstore(0x00, mulmod(mload(0x00), delta, r))
                    rhs := mulmod(rhs, addmod(addmod(calldataload(0x07e4), mload(0x00), r), gamma, r), r)
                    mstore(0x00, mulmod(mload(0x00), delta, r))
                    rhs := mulmod(rhs, addmod(addmod(calldataload(0x0804), mload(0x00), r), gamma, r), r)
                    mstore(0x00, mulmod(mload(0x00), delta, r))
                    rhs := mulmod(rhs, addmod(addmod(calldataload(0x0824), mload(0x00), r), gamma, r), r)
                    mstore(0x00, mulmod(mload(0x00), delta, r))
                    let left_sub_right := addmod(lhs, sub(r, rhs), r)
                    let eval := addmod(left_sub_right, sub(r, mulmod(left_sub_right, addmod(mload(L_LAST_MPTR), mload(L_BLIND_MPTR), r), r)), r)
                    quotient_eval_numer := addmod(mulmod(quotient_eval_numer, y, r), eval, r)
                }
                {
                    let gamma := mload(GAMMA_MPTR)
                    let beta := mload(BETA_MPTR)
                    let lhs := calldataload(0x0de4)
                    let rhs := calldataload(0x0dc4)
                    lhs := mulmod(lhs, addmod(addmod(calldataload(0x0844), mulmod(beta, calldataload(0x0cc4), r), r), gamma, r), r)
                    lhs := mulmod(lhs, addmod(addmod(mload(INSTANCE_EVAL_MPTR), mulmod(beta, calldataload(0x0ce4), r), r), gamma, r), r)
                    lhs := mulmod(lhs, addmod(addmod(calldataload(0x0ac4), mulmod(beta, calldataload(0x0d04), r), r), gamma, r), r)
                    lhs := mulmod(lhs, addmod(addmod(calldataload(0x0ae4), mulmod(beta, calldataload(0x0d24), r), r), gamma, r), r)
                    rhs := mulmod(rhs, addmod(addmod(calldataload(0x0844), mload(0x00), r), gamma, r), r)
                    mstore(0x00, mulmod(mload(0x00), delta, r))
                    rhs := mulmod(rhs, addmod(addmod(mload(INSTANCE_EVAL_MPTR), mload(0x00), r), gamma, r), r)
                    mstore(0x00, mulmod(mload(0x00), delta, r))
                    rhs := mulmod(rhs, addmod(addmod(calldataload(0x0ac4), mload(0x00), r), gamma, r), r)
                    mstore(0x00, mulmod(mload(0x00), delta, r))
                    rhs := mulmod(rhs, addmod(addmod(calldataload(0x0ae4), mload(0x00), r), gamma, r), r)
                    mstore(0x00, mulmod(mload(0x00), delta, r))
                    let left_sub_right := addmod(lhs, sub(r, rhs), r)
                    let eval := addmod(left_sub_right, sub(r, mulmod(left_sub_right, addmod(mload(L_LAST_MPTR), mload(L_BLIND_MPTR), r), r)), r)
                    quotient_eval_numer := addmod(mulmod(quotient_eval_numer, y, r), eval, r)
                }
                {
                    let gamma := mload(GAMMA_MPTR)
                    let beta := mload(BETA_MPTR)
                    let lhs := calldataload(0x0e44)
                    let rhs := calldataload(0x0e24)
                    lhs := mulmod(lhs, addmod(addmod(calldataload(0x0b04), mulmod(beta, calldataload(0x0d44), r), r), gamma, r), r)
                    rhs := mulmod(rhs, addmod(addmod(calldataload(0x0b04), mload(0x00), r), gamma, r), r)
                    let left_sub_right := addmod(lhs, sub(r, rhs), r)
                    let eval := addmod(left_sub_right, sub(r, mulmod(left_sub_right, addmod(mload(L_LAST_MPTR), mload(L_BLIND_MPTR), r), r)), r)
                    quotient_eval_numer := addmod(mulmod(quotient_eval_numer, y, r), eval, r)
                }
                {
                    let l_0 := mload(L_0_MPTR)
                    let eval := addmod(l_0, mulmod(l_0, sub(r, calldataload(0x0e64)), r), r)
                    quotient_eval_numer := addmod(mulmod(quotient_eval_numer, y, r), eval, r)
                }
                {
                    let l_last := mload(L_LAST_MPTR)
                    let eval := mulmod(l_last, addmod(mulmod(calldataload(0x0e64), calldataload(0x0e64), r), sub(r, calldataload(0x0e64)), r), r)
                    quotient_eval_numer := addmod(mulmod(quotient_eval_numer, y, r), eval, r)
                }
                {
                    let theta := mload(THETA_MPTR)
                    let input
                    {
                        let f_18 := calldataload(0x0b84)
                        let var0 := 0x5
                        let var1 := mulmod(f_18, var0, r)
                        let a_0 := calldataload(0x07c4)
                        let var2 := mulmod(f_18, a_0, r)
                        input := var1
                        input := addmod(mulmod(input, theta, r), var2, r)
                    }
                    let table
                    {
                        let f_9 := calldataload(0x0a64)
                        let f_10 := calldataload(0x0a84)
                        table := f_9
                        table := addmod(mulmod(table, theta, r), f_10, r)
                    }
                    let beta := mload(BETA_MPTR)
                    let gamma := mload(GAMMA_MPTR)
                    let lhs := mulmod(calldataload(0x0e84), mulmod(addmod(calldataload(0x0ea4), beta, r), addmod(calldataload(0x0ee4), gamma, r), r), r)
                    let rhs := mulmod(calldataload(0x0e64), mulmod(addmod(input, beta, r), addmod(table, gamma, r), r), r)
                    let eval := mulmod(addmod(1, sub(r, addmod(mload(L_BLIND_MPTR), mload(L_LAST_MPTR), r)), r), addmod(lhs, sub(r, rhs), r), r)
                    quotient_eval_numer := addmod(mulmod(quotient_eval_numer, y, r), eval, r)
                }
                {
                    let eval := mulmod(mload(L_0_MPTR), addmod(calldataload(0x0ea4), sub(r, calldataload(0x0ee4)), r), r)
                    quotient_eval_numer := addmod(mulmod(quotient_eval_numer, y, r), eval, r)
                }
                {
                    let eval := mulmod(addmod(1, sub(r, addmod(mload(L_BLIND_MPTR), mload(L_LAST_MPTR), r)), r), mulmod(addmod(calldataload(0x0ea4), sub(r, calldataload(0x0ee4)), r), addmod(calldataload(0x0ea4), sub(r, calldataload(0x0ec4)), r), r), r)
                    quotient_eval_numer := addmod(mulmod(quotient_eval_numer, y, r), eval, r)
                }
                {
                    let l_0 := mload(L_0_MPTR)
                    let eval := addmod(l_0, mulmod(l_0, sub(r, calldataload(0x0f04)), r), r)
                    quotient_eval_numer := addmod(mulmod(quotient_eval_numer, y, r), eval, r)
                }
                {
                    let l_last := mload(L_LAST_MPTR)
                    let eval := mulmod(l_last, addmod(mulmod(calldataload(0x0f04), calldataload(0x0f04), r), sub(r, calldataload(0x0f04)), r), r)
                    quotient_eval_numer := addmod(mulmod(quotient_eval_numer, y, r), eval, r)
                }
                {
                    let theta := mload(THETA_MPTR)
                    let input
                    {
                        let f_18 := calldataload(0x0b84)
                        let var0 := 0x5
                        let var1 := mulmod(f_18, var0, r)
                        let a_1 := calldataload(0x07e4)
                        let var2 := mulmod(f_18, a_1, r)
                        input := var1
                        input := addmod(mulmod(input, theta, r), var2, r)
                    }
                    let table
                    {
                        let f_9 := calldataload(0x0a64)
                        let f_10 := calldataload(0x0a84)
                        table := f_9
                        table := addmod(mulmod(table, theta, r), f_10, r)
                    }
                    let beta := mload(BETA_MPTR)
                    let gamma := mload(GAMMA_MPTR)
                    let lhs := mulmod(calldataload(0x0f24), mulmod(addmod(calldataload(0x0f44), beta, r), addmod(calldataload(0x0f84), gamma, r), r), r)
                    let rhs := mulmod(calldataload(0x0f04), mulmod(addmod(input, beta, r), addmod(table, gamma, r), r), r)
                    let eval := mulmod(addmod(1, sub(r, addmod(mload(L_BLIND_MPTR), mload(L_LAST_MPTR), r)), r), addmod(lhs, sub(r, rhs), r), r)
                    quotient_eval_numer := addmod(mulmod(quotient_eval_numer, y, r), eval, r)
                }
                {
                    let eval := mulmod(mload(L_0_MPTR), addmod(calldataload(0x0f44), sub(r, calldataload(0x0f84)), r), r)
                    quotient_eval_numer := addmod(mulmod(quotient_eval_numer, y, r), eval, r)
                }
                {
                    let eval := mulmod(addmod(1, sub(r, addmod(mload(L_BLIND_MPTR), mload(L_LAST_MPTR), r)), r), mulmod(addmod(calldataload(0x0f44), sub(r, calldataload(0x0f84)), r), addmod(calldataload(0x0f44), sub(r, calldataload(0x0f64)), r), r), r)
                    quotient_eval_numer := addmod(mulmod(quotient_eval_numer, y, r), eval, r)
                }
                {
                    let l_0 := mload(L_0_MPTR)
                    let eval := addmod(l_0, mulmod(l_0, sub(r, calldataload(0x0fa4)), r), r)
                    quotient_eval_numer := addmod(mulmod(quotient_eval_numer, y, r), eval, r)
                }
                {
                    let l_last := mload(L_LAST_MPTR)
                    let eval := mulmod(l_last, addmod(mulmod(calldataload(0x0fa4), calldataload(0x0fa4), r), sub(r, calldataload(0x0fa4)), r), r)
                    quotient_eval_numer := addmod(mulmod(quotient_eval_numer, y, r), eval, r)
                }
                {
                    let theta := mload(THETA_MPTR)
                    let input
                    {
                        let f_18 := calldataload(0x0b84)
                        let var0 := 0x5
                        let var1 := mulmod(f_18, var0, r)
                        let a_2 := calldataload(0x0804)
                        let var2 := mulmod(f_18, a_2, r)
                        input := var1
                        input := addmod(mulmod(input, theta, r), var2, r)
                    }
                    let table
                    {
                        let f_9 := calldataload(0x0a64)
                        let f_10 := calldataload(0x0a84)
                        table := f_9
                        table := addmod(mulmod(table, theta, r), f_10, r)
                    }
                    let beta := mload(BETA_MPTR)
                    let gamma := mload(GAMMA_MPTR)
                    let lhs := mulmod(calldataload(0x0fc4), mulmod(addmod(calldataload(0x0fe4), beta, r), addmod(calldataload(0x1024), gamma, r), r), r)
                    let rhs := mulmod(calldataload(0x0fa4), mulmod(addmod(input, beta, r), addmod(table, gamma, r), r), r)
                    let eval := mulmod(addmod(1, sub(r, addmod(mload(L_BLIND_MPTR), mload(L_LAST_MPTR), r)), r), addmod(lhs, sub(r, rhs), r), r)
                    quotient_eval_numer := addmod(mulmod(quotient_eval_numer, y, r), eval, r)
                }
                {
                    let eval := mulmod(mload(L_0_MPTR), addmod(calldataload(0x0fe4), sub(r, calldataload(0x1024)), r), r)
                    quotient_eval_numer := addmod(mulmod(quotient_eval_numer, y, r), eval, r)
                }
                {
                    let eval := mulmod(addmod(1, sub(r, addmod(mload(L_BLIND_MPTR), mload(L_LAST_MPTR), r)), r), mulmod(addmod(calldataload(0x0fe4), sub(r, calldataload(0x1024)), r), addmod(calldataload(0x0fe4), sub(r, calldataload(0x1004)), r), r), r)
                    quotient_eval_numer := addmod(mulmod(quotient_eval_numer, y, r), eval, r)
                }
                {
                    let l_0 := mload(L_0_MPTR)
                    let eval := addmod(l_0, mulmod(l_0, sub(r, calldataload(0x1044)), r), r)
                    quotient_eval_numer := addmod(mulmod(quotient_eval_numer, y, r), eval, r)
                }
                {
                    let l_last := mload(L_LAST_MPTR)
                    let eval := mulmod(l_last, addmod(mulmod(calldataload(0x1044), calldataload(0x1044), r), sub(r, calldataload(0x1044)), r), r)
                    quotient_eval_numer := addmod(mulmod(quotient_eval_numer, y, r), eval, r)
                }
                {
                    let theta := mload(THETA_MPTR)
                    let input
                    {
                        let f_18 := calldataload(0x0b84)
                        let var0 := 0x5
                        let var1 := mulmod(f_18, var0, r)
                        let a_3 := calldataload(0x0824)
                        let var2 := mulmod(f_18, a_3, r)
                        input := var1
                        input := addmod(mulmod(input, theta, r), var2, r)
                    }
                    let table
                    {
                        let f_9 := calldataload(0x0a64)
                        let f_10 := calldataload(0x0a84)
                        table := f_9
                        table := addmod(mulmod(table, theta, r), f_10, r)
                    }
                    let beta := mload(BETA_MPTR)
                    let gamma := mload(GAMMA_MPTR)
                    let lhs := mulmod(calldataload(0x1064), mulmod(addmod(calldataload(0x1084), beta, r), addmod(calldataload(0x10c4), gamma, r), r), r)
                    let rhs := mulmod(calldataload(0x1044), mulmod(addmod(input, beta, r), addmod(table, gamma, r), r), r)
                    let eval := mulmod(addmod(1, sub(r, addmod(mload(L_BLIND_MPTR), mload(L_LAST_MPTR), r)), r), addmod(lhs, sub(r, rhs), r), r)
                    quotient_eval_numer := addmod(mulmod(quotient_eval_numer, y, r), eval, r)
                }
                {
                    let eval := mulmod(mload(L_0_MPTR), addmod(calldataload(0x1084), sub(r, calldataload(0x10c4)), r), r)
                    quotient_eval_numer := addmod(mulmod(quotient_eval_numer, y, r), eval, r)
                }
                {
                    let eval := mulmod(addmod(1, sub(r, addmod(mload(L_BLIND_MPTR), mload(L_LAST_MPTR), r)), r), mulmod(addmod(calldataload(0x1084), sub(r, calldataload(0x10c4)), r), addmod(calldataload(0x1084), sub(r, calldataload(0x10a4)), r), r), r)
                    quotient_eval_numer := addmod(mulmod(quotient_eval_numer, y, r), eval, r)
                }
                {
                    let l_0 := mload(L_0_MPTR)
                    let eval := addmod(l_0, mulmod(l_0, sub(r, calldataload(0x10e4)), r), r)
                    quotient_eval_numer := addmod(mulmod(quotient_eval_numer, y, r), eval, r)
                }
                {
                    let l_last := mload(L_LAST_MPTR)
                    let eval := mulmod(l_last, addmod(mulmod(calldataload(0x10e4), calldataload(0x10e4), r), sub(r, calldataload(0x10e4)), r), r)
                    quotient_eval_numer := addmod(mulmod(quotient_eval_numer, y, r), eval, r)
                }
                {
                    let theta := mload(THETA_MPTR)
                    let input
                    {
                        let f_11 := calldataload(0x0aa4)
                        let f_19 := calldataload(0x0ba4)
                        let a_0 := calldataload(0x07c4)
                        let var0 := mulmod(f_19, a_0, r)
                        input := f_11
                        input := addmod(mulmod(input, theta, r), var0, r)
                    }
                    let table
                    {
                        let f_9 := calldataload(0x0a64)
                        let f_10 := calldataload(0x0a84)
                        table := f_9
                        table := addmod(mulmod(table, theta, r), f_10, r)
                    }
                    let beta := mload(BETA_MPTR)
                    let gamma := mload(GAMMA_MPTR)
                    let lhs := mulmod(calldataload(0x1104), mulmod(addmod(calldataload(0x1124), beta, r), addmod(calldataload(0x1164), gamma, r), r), r)
                    let rhs := mulmod(calldataload(0x10e4), mulmod(addmod(input, beta, r), addmod(table, gamma, r), r), r)
                    let eval := mulmod(addmod(1, sub(r, addmod(mload(L_BLIND_MPTR), mload(L_LAST_MPTR), r)), r), addmod(lhs, sub(r, rhs), r), r)
                    quotient_eval_numer := addmod(mulmod(quotient_eval_numer, y, r), eval, r)
                }
                {
                    let eval := mulmod(mload(L_0_MPTR), addmod(calldataload(0x1124), sub(r, calldataload(0x1164)), r), r)
                    quotient_eval_numer := addmod(mulmod(quotient_eval_numer, y, r), eval, r)
                }
                {
                    let eval := mulmod(addmod(1, sub(r, addmod(mload(L_BLIND_MPTR), mload(L_LAST_MPTR), r)), r), mulmod(addmod(calldataload(0x1124), sub(r, calldataload(0x1164)), r), addmod(calldataload(0x1124), sub(r, calldataload(0x1144)), r), r), r)
                    quotient_eval_numer := addmod(mulmod(quotient_eval_numer, y, r), eval, r)
                }

                pop(y)
                pop(delta)

                let quotient_eval := mulmod(quotient_eval_numer, mload(X_N_MINUS_1_INV_MPTR), r)
                mstore(QUOTIENT_EVAL_MPTR, quotient_eval)
            }

            // Compute quotient commitment
            {
                mstore(0x00, calldataload(LAST_QUOTIENT_X_CPTR))
                mstore(0x20, calldataload(add(LAST_QUOTIENT_X_CPTR, 0x20)))
                let x_n := mload(X_N_MPTR)
                for
                    {
                        let cptr := sub(LAST_QUOTIENT_X_CPTR, 0x40)
                        let cptr_end := sub(FIRST_QUOTIENT_X_CPTR, 0x40)
                    }
                    lt(cptr_end, cptr)
                    {}
                {
                    success := ec_mul_acc(success, x_n)
                    success := ec_add_acc(success, calldataload(cptr), calldataload(add(cptr, 0x20)))
                    cptr := sub(cptr, 0x40)
                }
                mstore(QUOTIENT_X_MPTR, mload(0x00))
                mstore(QUOTIENT_Y_MPTR, mload(0x20))
            }

            // Compute pairing lhs and rhs
            {
                {
                    let x := mload(X_MPTR)
                    let omega := mload(OMEGA_MPTR)
                    let omega_inv := mload(OMEGA_INV_MPTR)
                    let x_pow_of_omega := mulmod(x, omega, r)
                    mstore(0x0420, x_pow_of_omega)
                    mstore(0x0400, x)
                    x_pow_of_omega := mulmod(x, omega_inv, r)
                    mstore(0x03e0, x_pow_of_omega)
                    x_pow_of_omega := mulmod(x_pow_of_omega, omega_inv, r)
                    x_pow_of_omega := mulmod(x_pow_of_omega, omega_inv, r)
                    x_pow_of_omega := mulmod(x_pow_of_omega, omega_inv, r)
                    x_pow_of_omega := mulmod(x_pow_of_omega, omega_inv, r)
                    x_pow_of_omega := mulmod(x_pow_of_omega, omega_inv, r)
                    mstore(0x03c0, x_pow_of_omega)
                }
                {
                    let mu := mload(MU_MPTR)
                    for
                        {
                            let mptr := 0x0440
                            let mptr_end := 0x04c0
                            let point_mptr := 0x03c0
                        }
                        lt(mptr, mptr_end)
                        {
                            mptr := add(mptr, 0x20)
                            point_mptr := add(point_mptr, 0x20)
                        }
                    {
                        mstore(mptr, addmod(mu, sub(r, mload(point_mptr)), r))
                    }
                    let s
                    s := mload(0x0460)
                    s := mulmod(s, mload(0x0480), r)
                    s := mulmod(s, mload(0x04a0), r)
                    mstore(0x04c0, s)
                    let diff
                    diff := mload(0x0440)
                    mstore(0x04e0, diff)
                    mstore(0x00, diff)
                    diff := mload(0x0440)
                    diff := mulmod(diff, mload(0x0460), r)
                    diff := mulmod(diff, mload(0x04a0), r)
                    mstore(0x0500, diff)
                    diff := mload(0x0440)
                    diff := mulmod(diff, mload(0x0460), r)
                    mstore(0x0520, diff)
                    diff := mload(0x0460)
                    mstore(0x0540, diff)
                    diff := mload(0x0440)
                    diff := mulmod(diff, mload(0x04a0), r)
                    mstore(0x0560, diff)
                }
                {
                    let point_1 := mload(0x03e0)
                    let point_2 := mload(0x0400)
                    let point_3 := mload(0x0420)
                    let coeff
                    coeff := addmod(point_1, sub(r, point_2), r)
                    coeff := mulmod(coeff, addmod(point_1, sub(r, point_3), r), r)
                    coeff := mulmod(coeff, mload(0x0460), r)
                    mstore(0x20, coeff)
                    coeff := addmod(point_2, sub(r, point_1), r)
                    coeff := mulmod(coeff, addmod(point_2, sub(r, point_3), r), r)
                    coeff := mulmod(coeff, mload(0x0480), r)
                    mstore(0x40, coeff)
                    coeff := addmod(point_3, sub(r, point_1), r)
                    coeff := mulmod(coeff, addmod(point_3, sub(r, point_2), r), r)
                    coeff := mulmod(coeff, mload(0x04a0), r)
                    mstore(0x60, coeff)
                }
                {
                    let point_2 := mload(0x0400)
                    let coeff
                    coeff := 1
                    coeff := mulmod(coeff, mload(0x0480), r)
                    mstore(0x80, coeff)
                }
                {
                    let point_2 := mload(0x0400)
                    let point_3 := mload(0x0420)
                    let coeff
                    coeff := addmod(point_2, sub(r, point_3), r)
                    coeff := mulmod(coeff, mload(0x0480), r)
                    mstore(0xa0, coeff)
                    coeff := addmod(point_3, sub(r, point_2), r)
                    coeff := mulmod(coeff, mload(0x04a0), r)
                    mstore(0xc0, coeff)
                }
                {
                    let point_0 := mload(0x03c0)
                    let point_2 := mload(0x0400)
                    let point_3 := mload(0x0420)
                    let coeff
                    coeff := addmod(point_0, sub(r, point_2), r)
                    coeff := mulmod(coeff, addmod(point_0, sub(r, point_3), r), r)
                    coeff := mulmod(coeff, mload(0x0440), r)
                    mstore(0xe0, coeff)
                    coeff := addmod(point_2, sub(r, point_0), r)
                    coeff := mulmod(coeff, addmod(point_2, sub(r, point_3), r), r)
                    coeff := mulmod(coeff, mload(0x0480), r)
                    mstore(0x0100, coeff)
                    coeff := addmod(point_3, sub(r, point_0), r)
                    coeff := mulmod(coeff, addmod(point_3, sub(r, point_2), r), r)
                    coeff := mulmod(coeff, mload(0x04a0), r)
                    mstore(0x0120, coeff)
                }
                {
                    let point_1 := mload(0x03e0)
                    let point_2 := mload(0x0400)
                    let coeff
                    coeff := addmod(point_1, sub(r, point_2), r)
                    coeff := mulmod(coeff, mload(0x0460), r)
                    mstore(0x0140, coeff)
                    coeff := addmod(point_2, sub(r, point_1), r)
                    coeff := mulmod(coeff, mload(0x0480), r)
                    mstore(0x0160, coeff)
                }
                {
                    success := batch_invert(success, 0, 0x0180, r)
                    let diff_0_inv := mload(0x00)
                    mstore(0x04e0, diff_0_inv)
                    for
                        {
                            let mptr := 0x0500
                            let mptr_end := 0x0580
                        }
                        lt(mptr, mptr_end)
                        { mptr := add(mptr, 0x20) }
                    {
                        mstore(mptr, mulmod(mload(mptr), diff_0_inv, r))
                    }
                }
                {
                    let zeta := mload(ZETA_MPTR)
                    let r_eval := 0
                    r_eval := addmod(r_eval, mulmod(mload(0x20), calldataload(0x08e4), r), r)
                    r_eval := addmod(r_eval, mulmod(mload(0x40), calldataload(0x0804), r), r)
                    r_eval := addmod(r_eval, mulmod(mload(0x60), calldataload(0x08c4), r), r)
                    r_eval := mulmod(r_eval, zeta, r)
                    r_eval := addmod(r_eval, mulmod(mload(0x20), calldataload(0x0924), r), r)
                    r_eval := addmod(r_eval, mulmod(mload(0x40), calldataload(0x07e4), r), r)
                    r_eval := addmod(r_eval, mulmod(mload(0x60), calldataload(0x08a4), r), r)
                    r_eval := mulmod(r_eval, zeta, r)
                    r_eval := addmod(r_eval, mulmod(mload(0x20), calldataload(0x0904), r), r)
                    r_eval := addmod(r_eval, mulmod(mload(0x40), calldataload(0x07c4), r), r)
                    r_eval := addmod(r_eval, mulmod(mload(0x60), calldataload(0x0884), r), r)
                    mstore(0x0580, r_eval)
                }
                {
                    let coeff := mload(0x80)
                    let zeta := mload(ZETA_MPTR)
                    let r_eval := 0
                    r_eval := addmod(r_eval, mulmod(coeff, calldataload(0x0c24), r), r)
                    r_eval := mulmod(r_eval, zeta, r)
                    r_eval := addmod(r_eval, mulmod(coeff, mload(QUOTIENT_EVAL_MPTR), r), r)
                    for
                        {
                            let mptr := 0x0d44
                            let mptr_end := 0x0c24
                        }
                        lt(mptr_end, mptr)
                        { mptr := sub(mptr, 0x20) }
                    {
                        r_eval := addmod(mulmod(r_eval, zeta, r), mulmod(coeff, calldataload(mptr), r), r)
                    }
                    for
                        {
                            let mptr := 0x0c04
                            let mptr_end := 0x0924
                        }
                        lt(mptr_end, mptr)
                        { mptr := sub(mptr, 0x20) }
                    {
                        r_eval := addmod(mulmod(r_eval, zeta, r), mulmod(coeff, calldataload(mptr), r), r)
                    }
                    r_eval := mulmod(r_eval, zeta, r)
                    r_eval := addmod(r_eval, mulmod(coeff, calldataload(0x1164), r), r)
                    r_eval := mulmod(r_eval, zeta, r)
                    r_eval := addmod(r_eval, mulmod(coeff, calldataload(0x10c4), r), r)
                    r_eval := mulmod(r_eval, zeta, r)
                    r_eval := addmod(r_eval, mulmod(coeff, calldataload(0x1024), r), r)
                    r_eval := mulmod(r_eval, zeta, r)
                    r_eval := addmod(r_eval, mulmod(coeff, calldataload(0x0f84), r), r)
                    r_eval := mulmod(r_eval, zeta, r)
                    r_eval := addmod(r_eval, mulmod(coeff, calldataload(0x0ee4), r), r)
                    r_eval := mulmod(r_eval, zeta, r)
                    r_eval := addmod(r_eval, mulmod(coeff, calldataload(0x0824), r), r)
                    r_eval := mulmod(r_eval, mload(0x0500), r)
                    mstore(0x05a0, r_eval)
                }
                {
                    let zeta := mload(ZETA_MPTR)
                    let r_eval := 0
                    r_eval := addmod(r_eval, mulmod(mload(0xa0), calldataload(0x10e4), r), r)
                    r_eval := addmod(r_eval, mulmod(mload(0xc0), calldataload(0x1104), r), r)
                    r_eval := mulmod(r_eval, zeta, r)
                    r_eval := addmod(r_eval, mulmod(mload(0xa0), calldataload(0x1044), r), r)
                    r_eval := addmod(r_eval, mulmod(mload(0xc0), calldataload(0x1064), r), r)
                    r_eval := mulmod(r_eval, zeta, r)
                    r_eval := addmod(r_eval, mulmod(mload(0xa0), calldataload(0x0fa4), r), r)
                    r_eval := addmod(r_eval, mulmod(mload(0xc0), calldataload(0x0fc4), r), r)
                    r_eval := mulmod(r_eval, zeta, r)
                    r_eval := addmod(r_eval, mulmod(mload(0xa0), calldataload(0x0f04), r), r)
                    r_eval := addmod(r_eval, mulmod(mload(0xc0), calldataload(0x0f24), r), r)
                    r_eval := mulmod(r_eval, zeta, r)
                    r_eval := addmod(r_eval, mulmod(mload(0xa0), calldataload(0x0e64), r), r)
                    r_eval := addmod(r_eval, mulmod(mload(0xc0), calldataload(0x0e84), r), r)
                    r_eval := mulmod(r_eval, zeta, r)
                    r_eval := addmod(r_eval, mulmod(mload(0xa0), calldataload(0x0e24), r), r)
                    r_eval := addmod(r_eval, mulmod(mload(0xc0), calldataload(0x0e44), r), r)
                    r_eval := mulmod(r_eval, zeta, r)
                    r_eval := addmod(r_eval, mulmod(mload(0xa0), calldataload(0x0844), r), r)
                    r_eval := addmod(r_eval, mulmod(mload(0xc0), calldataload(0x0864), r), r)
                    r_eval := mulmod(r_eval, mload(0x0520), r)
                    mstore(0x05c0, r_eval)
                }
                {
                    let zeta := mload(ZETA_MPTR)
                    let r_eval := 0
                    r_eval := addmod(r_eval, mulmod(mload(0xe0), calldataload(0x0e04), r), r)
                    r_eval := addmod(r_eval, mulmod(mload(0x0100), calldataload(0x0dc4), r), r)
                    r_eval := addmod(r_eval, mulmod(mload(0x0120), calldataload(0x0de4), r), r)
                    r_eval := mulmod(r_eval, zeta, r)
                    r_eval := addmod(r_eval, mulmod(mload(0xe0), calldataload(0x0da4), r), r)
                    r_eval := addmod(r_eval, mulmod(mload(0x0100), calldataload(0x0d64), r), r)
                    r_eval := addmod(r_eval, mulmod(mload(0x0120), calldataload(0x0d84), r), r)
                    r_eval := mulmod(r_eval, mload(0x0540), r)
                    mstore(0x05e0, r_eval)
                }
                {
                    let zeta := mload(ZETA_MPTR)
                    let r_eval := 0
                    r_eval := addmod(r_eval, mulmod(mload(0x0140), calldataload(0x1144), r), r)
                    r_eval := addmod(r_eval, mulmod(mload(0x0160), calldataload(0x1124), r), r)
                    r_eval := mulmod(r_eval, zeta, r)
                    r_eval := addmod(r_eval, mulmod(mload(0x0140), calldataload(0x10a4), r), r)
                    r_eval := addmod(r_eval, mulmod(mload(0x0160), calldataload(0x1084), r), r)
                    r_eval := mulmod(r_eval, zeta, r)
                    r_eval := addmod(r_eval, mulmod(mload(0x0140), calldataload(0x1004), r), r)
                    r_eval := addmod(r_eval, mulmod(mload(0x0160), calldataload(0x0fe4), r), r)
                    r_eval := mulmod(r_eval, zeta, r)
                    r_eval := addmod(r_eval, mulmod(mload(0x0140), calldataload(0x0f64), r), r)
                    r_eval := addmod(r_eval, mulmod(mload(0x0160), calldataload(0x0f44), r), r)
                    r_eval := mulmod(r_eval, zeta, r)
                    r_eval := addmod(r_eval, mulmod(mload(0x0140), calldataload(0x0ec4), r), r)
                    r_eval := addmod(r_eval, mulmod(mload(0x0160), calldataload(0x0ea4), r), r)
                    r_eval := mulmod(r_eval, mload(0x0560), r)
                    mstore(0x0600, r_eval)
                }
                {
                    let sum := mload(0x20)
                    sum := addmod(sum, mload(0x40), r)
                    sum := addmod(sum, mload(0x60), r)
                    mstore(0x0620, sum)
                }
                {
                    let sum := mload(0x80)
                    mstore(0x0640, sum)
                }
                {
                    let sum := mload(0xa0)
                    sum := addmod(sum, mload(0xc0), r)
                    mstore(0x0660, sum)
                }
                {
                    let sum := mload(0xe0)
                    sum := addmod(sum, mload(0x0100), r)
                    sum := addmod(sum, mload(0x0120), r)
                    mstore(0x0680, sum)
                }
                {
                    let sum := mload(0x0140)
                    sum := addmod(sum, mload(0x0160), r)
                    mstore(0x06a0, sum)
                }
                {
                    for
                        {
                            let mptr := 0x00
                            let mptr_end := 0xa0
                            let sum_mptr := 0x0620
                        }
                        lt(mptr, mptr_end)
                        {
                            mptr := add(mptr, 0x20)
                            sum_mptr := add(sum_mptr, 0x20)
                        }
                    {
                        mstore(mptr, mload(sum_mptr))
                    }
                    success := batch_invert(success, 0, 0xa0, r)
                    let r_eval := mulmod(mload(0x80), mload(0x0600), r)
                    for
                        {
                            let sum_inv_mptr := 0x60
                            let sum_inv_mptr_end := 0xa0
                            let r_eval_mptr := 0x05e0
                        }
                        lt(sum_inv_mptr, sum_inv_mptr_end)
                        {
                            sum_inv_mptr := sub(sum_inv_mptr, 0x20)
                            r_eval_mptr := sub(r_eval_mptr, 0x20)
                        }
                    {
                        r_eval := mulmod(r_eval, mload(NU_MPTR), r)
                        r_eval := addmod(r_eval, mulmod(mload(sum_inv_mptr), mload(r_eval_mptr), r), r)
                    }
                    mstore(R_EVAL_MPTR, r_eval)
                }
                {
                    let nu := mload(NU_MPTR)
                    mstore(0x00, calldataload(0x0104))
                    mstore(0x20, calldataload(0x0124))
                    success := ec_mul_acc(success, mload(ZETA_MPTR))
                    success := ec_add_acc(success, calldataload(0xc4), calldataload(0xe4))
                    success := ec_mul_acc(success, mload(ZETA_MPTR))
                    success := ec_add_acc(success, calldataload(0x84), calldataload(0xa4))
                    mstore(0x80, calldataload(0x0644))
                    mstore(0xa0, calldataload(0x0664))
                    success := ec_mul_tmp(success, mload(ZETA_MPTR))
                    success := ec_add_tmp(success, mload(QUOTIENT_X_MPTR), mload(QUOTIENT_Y_MPTR))
                    for
                        {
                            let mptr := 0x1120
                            let mptr_end := 0x0da0
                        }
                        lt(mptr_end, mptr)
                        { mptr := sub(mptr, 0x40) }
                    {
                        success := ec_mul_tmp(success, mload(ZETA_MPTR))
                        success := ec_add_tmp(success, mload(mptr), mload(add(mptr, 0x20)))
                    }
                    for
                        {
                            let mptr := 0x0ce0
                            let mptr_end := 0x0c20
                        }
                        lt(mptr_end, mptr)
                        { mptr := sub(mptr, 0x40) }
                    {
                        success := ec_mul_tmp(success, mload(ZETA_MPTR))
                        success := ec_add_tmp(success, mload(mptr), mload(add(mptr, 0x20)))
                    }
                    for
                        {
                            let mptr := 0x0da0
                            let mptr_end := 0x0ce0
                        }
                        lt(mptr_end, mptr)
                        { mptr := sub(mptr, 0x40) }
                    {
                        success := ec_mul_tmp(success, mload(ZETA_MPTR))
                        success := ec_add_tmp(success, mload(mptr), mload(add(mptr, 0x20)))
                    }
                    for
                        {
                            let mptr := 0x0c20
                            let mptr_end := 0x0b20
                        }
                        lt(mptr_end, mptr)
                        { mptr := sub(mptr, 0x40) }
                    {
                        success := ec_mul_tmp(success, mload(ZETA_MPTR))
                        success := ec_add_tmp(success, mload(mptr), mload(add(mptr, 0x20)))
                    }
                    success := ec_mul_tmp(success, mload(ZETA_MPTR))
                    success := ec_add_tmp(success, mload(0x0ae0), mload(0x0b00))
                    success := ec_mul_tmp(success, mload(ZETA_MPTR))
                    success := ec_add_tmp(success, mload(0x0aa0), mload(0x0ac0))
                    success := ec_mul_tmp(success, mload(ZETA_MPTR))
                    success := ec_add_tmp(success, mload(0x0b20), mload(0x0b40))
                    for
                        {
                            let mptr := 0x0a60
                            let mptr_end := 0x0920
                        }
                        lt(mptr_end, mptr)
                        { mptr := sub(mptr, 0x40) }
                    {
                        success := ec_mul_tmp(success, mload(ZETA_MPTR))
                        success := ec_add_tmp(success, mload(mptr), mload(add(mptr, 0x20)))
                    }
                    success := ec_mul_tmp(success, mload(ZETA_MPTR))
                    success := ec_add_tmp(success, calldataload(0x0404), calldataload(0x0424))
                    success := ec_mul_tmp(success, mload(ZETA_MPTR))
                    success := ec_add_tmp(success, calldataload(0x0384), calldataload(0x03a4))
                    success := ec_mul_tmp(success, mload(ZETA_MPTR))
                    success := ec_add_tmp(success, calldataload(0x0304), calldataload(0x0324))
                    success := ec_mul_tmp(success, mload(ZETA_MPTR))
                    success := ec_add_tmp(success, calldataload(0x0284), calldataload(0x02a4))
                    success := ec_mul_tmp(success, mload(ZETA_MPTR))
                    success := ec_add_tmp(success, calldataload(0x0204), calldataload(0x0224))
                    success := ec_mul_tmp(success, mload(ZETA_MPTR))
                    success := ec_add_tmp(success, calldataload(0x0144), calldataload(0x0164))
                    success := ec_mul_tmp(success, mulmod(nu, mload(0x0500), r))
                    success := ec_add_acc(success, mload(0x80), mload(0xa0))
                    nu := mulmod(nu, mload(NU_MPTR), r)
                    mstore(0x80, calldataload(0x0604))
                    mstore(0xa0, calldataload(0x0624))
                    for
                        {
                            let mptr := 0x05c4
                            let mptr_end := 0x0484
                        }
                        lt(mptr_end, mptr)
                        { mptr := sub(mptr, 0x40) }
                    {
                        success := ec_mul_tmp(success, mload(ZETA_MPTR))
                        success := ec_add_tmp(success, calldataload(mptr), calldataload(add(mptr, 0x20)))
                    }
                    success := ec_mul_tmp(success, mload(ZETA_MPTR))
                    success := ec_add_tmp(success, calldataload(0x0184), calldataload(0x01a4))
                    success := ec_mul_tmp(success, mulmod(nu, mload(0x0520), r))
                    success := ec_add_acc(success, mload(0x80), mload(0xa0))
                    nu := mulmod(nu, mload(NU_MPTR), r)
                    mstore(0x80, calldataload(0x0484))
                    mstore(0xa0, calldataload(0x04a4))
                    success := ec_mul_tmp(success, mload(ZETA_MPTR))
                    success := ec_add_tmp(success, calldataload(0x0444), calldataload(0x0464))
                    success := ec_mul_tmp(success, mulmod(nu, mload(0x0540), r))
                    success := ec_add_acc(success, mload(0x80), mload(0xa0))
                    nu := mulmod(nu, mload(NU_MPTR), r)
                    mstore(0x80, calldataload(0x03c4))
                    mstore(0xa0, calldataload(0x03e4))
                    success := ec_mul_tmp(success, mload(ZETA_MPTR))
                    success := ec_add_tmp(success, calldataload(0x0344), calldataload(0x0364))
                    success := ec_mul_tmp(success, mload(ZETA_MPTR))
                    success := ec_add_tmp(success, calldataload(0x02c4), calldataload(0x02e4))
                    success := ec_mul_tmp(success, mload(ZETA_MPTR))
                    success := ec_add_tmp(success, calldataload(0x0244), calldataload(0x0264))
                    success := ec_mul_tmp(success, mload(ZETA_MPTR))
                    success := ec_add_tmp(success, calldataload(0x01c4), calldataload(0x01e4))
                    success := ec_mul_tmp(success, mulmod(nu, mload(0x0560), r))
                    success := ec_add_acc(success, mload(0x80), mload(0xa0))
                    mstore(0x80, mload(G1_X_MPTR))
                    mstore(0xa0, mload(G1_Y_MPTR))
                    success := ec_mul_tmp(success, sub(r, mload(R_EVAL_MPTR)))
                    success := ec_add_acc(success, mload(0x80), mload(0xa0))
                    mstore(0x80, calldataload(0x1184))
                    mstore(0xa0, calldataload(0x11a4))
                    success := ec_mul_tmp(success, sub(r, mload(0x04c0)))
                    success := ec_add_acc(success, mload(0x80), mload(0xa0))
                    mstore(0x80, calldataload(0x11c4))
                    mstore(0xa0, calldataload(0x11e4))
                    success := ec_mul_tmp(success, mload(MU_MPTR))
                    success := ec_add_acc(success, mload(0x80), mload(0xa0))
                    mstore(PAIRING_LHS_X_MPTR, mload(0x00))
                    mstore(PAIRING_LHS_Y_MPTR, mload(0x20))
                    mstore(PAIRING_RHS_X_MPTR, calldataload(0x11c4))
                    mstore(PAIRING_RHS_Y_MPTR, calldataload(0x11e4))
                }
            }

            // Random linear combine with accumulator
            if mload(HAS_ACCUMULATOR_MPTR) {
                mstore(0x00, mload(ACC_LHS_X_MPTR))
                mstore(0x20, mload(ACC_LHS_Y_MPTR))
                mstore(0x40, mload(ACC_RHS_X_MPTR))
                mstore(0x60, mload(ACC_RHS_Y_MPTR))
                mstore(0x80, mload(PAIRING_LHS_X_MPTR))
                mstore(0xa0, mload(PAIRING_LHS_Y_MPTR))
                mstore(0xc0, mload(PAIRING_RHS_X_MPTR))
                mstore(0xe0, mload(PAIRING_RHS_Y_MPTR))
                let challenge := mod(keccak256(0x00, 0x100), r)

                // [pairing_lhs] += challenge * [acc_lhs]
                success := ec_mul_acc(success, challenge)
                success := ec_add_acc(success, mload(PAIRING_LHS_X_MPTR), mload(PAIRING_LHS_Y_MPTR))
                mstore(PAIRING_LHS_X_MPTR, mload(0x00))
                mstore(PAIRING_LHS_Y_MPTR, mload(0x20))

                // [pairing_rhs] += challenge * [acc_rhs]
                mstore(0x00, mload(ACC_RHS_X_MPTR))
                mstore(0x20, mload(ACC_RHS_Y_MPTR))
                success := ec_mul_acc(success, challenge)
                success := ec_add_acc(success, mload(PAIRING_RHS_X_MPTR), mload(PAIRING_RHS_Y_MPTR))
                mstore(PAIRING_RHS_X_MPTR, mload(0x00))
                mstore(PAIRING_RHS_Y_MPTR, mload(0x20))
            }

            // Perform pairing
            success := ec_pairing(
                success,
                mload(PAIRING_LHS_X_MPTR),
                mload(PAIRING_LHS_Y_MPTR),
                mload(PAIRING_RHS_X_MPTR),
                mload(PAIRING_RHS_Y_MPTR)
            )

            // Revert if anything fails
            if iszero(success) {
                revert(0x00, 0x00)
            }

            // Return 1 as result if everything succeeds
            mstore(0x00, 1)
            return(0x00, 0x20)
        }
    }
}