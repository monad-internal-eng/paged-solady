// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {LibBit} from "./LibBit.sol";

/// @notice Library for storage of packed unsigned booleans.
/// @author QEDK (@qedk)
/// @author Solady (https://github.com/vectorized/solady/blob/main/src/utils/LibBitmap.sol)
/// @author Modified from Solmate (https://github.com/transmissions11/solmate/blob/main/src/utils/LibBitmap.sol)
/// @author Modified from Solidity-Bits (https://github.com/estarriolvetch/solidity-bits/blob/main/contracts/BitMaps.sol)
library LibBitmap {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev The constant returned when a bitmap scan does not find a result.
    uint256 internal constant NOT_FOUND = type(uint256).max;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          STRUCTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev A bitmap in storage
    /// @dev _ptr serves as phantom data to provide a storage slot for the
    /// @dev bitmap. A page aligned slot is used to store the bitmap at
    /// @dev `keccak256(bitmap.slot) & not(0x7f)` and the bitmap is stored
    /// @dev serially in 256-bit buckets starting from that slot.
    struct Bitmap {
        uint256 _ptr;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         OPERATIONS                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Returns the boolean value of the bit at `index` in `bitmap`.
    function get(Bitmap storage bitmap, uint256 index) internal view returns (bool isSet) {
        // It is better to set `isSet` to either 0 or 1, than zero vs non-zero.
        // Both cost the same amount of gas, but the former allows the returned value
        // to be reused without cleaning the upper bits.
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, bitmap.slot) // store bitmap slot value
            let slot := and(keccak256(0x00, 0x20), not(0x7f))
            let bucket := sload(add(slot, shr(8, index))) // get bucket by shifting idx
            isSet := and(shr(and(index, 0xff), bucket), 1) // shift bucket to get bit at idx
        }
    }

    /// @dev Updates the bit at `index` in `bitmap` to true.
    function set(Bitmap storage bitmap, uint256 index) internal {
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, bitmap.slot)
            let slot := and(keccak256(0x00, 0x20), not(0x7f))
            let bucket := sload(add(slot, shr(8, index))) // get bucket by shifting idx
            sstore(add(slot, shr(8, index)), or(bucket, shl(and(index, 0xff), 1))) // set bit at idx
        }
    }

    /// @dev Updates the bit at `index` in `bitmap` to false.
    function unset(Bitmap storage bitmap, uint256 index) internal {
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, bitmap.slot)
            let slot := and(keccak256(0x00, 0x20), not(0x7f))
            let bucket := sload(add(slot, shr(8, index))) // get bucket by shifting idx
            sstore(add(slot, shr(8, index)), and(bucket, not(shl(and(index, 0xff), 1)))) // unset bit at idx
        }
    }

    /// @dev Flips the bit at `index` in `bitmap`.
    /// Returns the boolean result of the flipped bit.
    function toggle(Bitmap storage bitmap, uint256 index) internal returns (bool newIsSet) {
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, bitmap.slot)
            let slot := add(and(keccak256(0x00, 0x20), not(0x7f)), shr(8, index))
            let shift := and(index, 0xff)
            let storageValue := xor(sload(slot), shl(shift, 1))
            // It makes sense to return the `newIsSet`,
            // as it allow us to skip an additional warm `sload`,
            // and it costs minimal gas (about 15),
            // which may be optimized away if the returned value is unused.
            newIsSet := and(1, shr(shift, storageValue))
            sstore(slot, storageValue)
        }
    }

    /// @dev Updates the bit at `index` in `bitmap` to `shouldSet`.
    function setTo(Bitmap storage bitmap, uint256 index, bool shouldSet) internal {
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, bitmap.slot)
            let slot := add(and(keccak256(0x00, 0x20), not(0x7f)), shr(8, index))
            let storageValue := sload(slot) 
            let shift := and(index, 0xff)
            sstore(
                slot,
                // Unsets the bit at `shift` via `and`, then sets its new value via `or`.
                or(and(storageValue, not(shl(shift, 1))), shl(shift, iszero(iszero(shouldSet))))
            )
        }
    }

    /// @dev Consecutively sets `amount` of bits starting from the bit at `start`.
    function setBatch(Bitmap storage bitmap, uint256 start, uint256 amount) internal {
        /// @solidity memory-safe-assembly
        assembly {
            let max := not(0)
            let shift := and(start, 0xff)
            mstore(0x00, bitmap.slot)
            let base := and(keccak256(0x00, 0x20), not(0x7f))
            let bucket := shr(8, start) // bucket index
            if iszero(lt(add(shift, amount), 257)) {
                let slot := add(base, bucket)
                sstore(slot, or(sload(slot), shl(shift, max)))
                let bucketEnd := add(bucket, shr(8, add(amount, shift)))
                amount := and(add(amount, shift), 0xff)
                shift := 0
                for { bucket := add(bucket, 1)} iszero(eq(bucket, bucketEnd)) { bucket := add(bucket, 1) } {
                    sstore(add(base, bucket), max)
                }
            }
            let slot := add(base, bucket)
            sstore(slot, or(sload(slot), shl(shift, shr(sub(256, amount), max))))
        }
    }

    /// @dev Consecutively unsets `amount` of bits starting from the bit at `start`.
    function unsetBatch(Bitmap storage bitmap, uint256 start, uint256 amount) internal {
        /// @solidity memory-safe-assembly
        assembly {
            let shift := and(start, 0xff)
            mstore(0x00, bitmap.slot)
            let base := and(keccak256(0x00, 0x20), not(0x7f))
            let bucket := shr(8, start) // bucket index
            if iszero(lt(add(shift, amount), 257)) {
                let slot := add(base, bucket)
                sstore(slot, and(sload(slot), not(shl(shift, not(0)))))
                let bucketEnd := add(bucket, shr(8, add(amount, shift)))
                amount := and(add(amount, shift), 0xff)
                shift := 0
                for { bucket := add(bucket, 1)} iszero(eq(bucket, bucketEnd)) { bucket := add(bucket, 1) } {
                    sstore(add(base, bucket), 0)
                }
            }
            let slot := add(base, bucket)
            sstore(
                slot,
                and(sload(slot), not(shl(shift, shr(sub(256, amount), not(0)))))
            )
        }
    }

    /// @dev Returns number of set bits within a range by
    /// scanning `amount` of bits starting from the bit at `start`.
    function popCount(Bitmap storage bitmap, uint256 start, uint256 amount)
        internal
        view
        returns (uint256 count)
    {
        unchecked {
            uint256 bucket = start >> 8;
            uint256 shift = start & 0xff;
            uint256 base;
            /// @solidity memory-safe-assembly
            assembly {
                mstore(0x00, bitmap.slot)
                base := and(keccak256(0x00, 0x20), not(0x7f))
            }
            uint256 bucketValue;
            if (!(amount + shift < 257)) {
                /// @solidity memory-safe-assembly
                assembly {
                    bucketValue := sload(add(base, bucket))
                }
                count = LibBit.popCount(bucketValue >> shift);
                uint256 bucketEnd = bucket + ((amount + shift) >> 8);
                amount = (amount + shift) & 0xff;
                shift = 0;
                for (++bucket; bucket != bucketEnd; ++bucket) {
                    /// @solidity memory-safe-assembly
                    assembly {
                        bucketValue := sload(add(base, bucket))
                    }
                    count += LibBit.popCount(bucketValue);
                }
            }
            /// @solidity memory-safe-assembly
            assembly {
                bucketValue := sload(add(base, bucket))
            }
            count += LibBit.popCount((bucketValue >> shift) << (256 - amount));
        }
    }

    /// @dev Returns the index of the most significant set bit in `[0..upTo]`.
    /// If no set bit is found, returns `NOT_FOUND`.
    function findLastSet(Bitmap storage bitmap, uint256 upTo)
        internal
        view
        returns (uint256 setBitIndex)
    {
        setBitIndex = NOT_FOUND;
        uint256 bucket = upTo >> 8;
        uint256 bits;
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, bitmap.slot)
            let offset := and(0xff, not(upTo)) // `256 - (255 & upTo) - 1`.
            let base := and(keccak256(0x00, 0x20), not(0x7f))
            bits := shr(offset, shl(offset, sload(add(base, bucket)))) // `sload(add(base, bucket)) << offset >> offset`.
            if iszero(or(bits, iszero(bucket))) {
                for {} 1 {} {
                    bucket := add(bucket, setBitIndex) // `sub(bucket, 1)`.
                    bits := sload(add(base, bucket))
                    if or(bits, iszero(bucket)) { break }
                }
            }
        }
        if (bits != 0) {
            setBitIndex = (bucket << 8) | LibBit.fls(bits);
            /// @solidity memory-safe-assembly
            assembly {
                setBitIndex := or(setBitIndex, sub(0, gt(setBitIndex, upTo)))
            }
        }
    }

    /// @dev Returns the index of the least significant unset bit in `[begin..upTo]`.
    /// If no unset bit is found, returns `NOT_FOUND`.
    function findFirstUnset(Bitmap storage bitmap, uint256 begin, uint256 upTo)
        internal
        view
        returns (uint256 unsetBitIndex)
    {
        unsetBitIndex = NOT_FOUND;
        uint256 bucket = begin >> 8;
        uint256 negBits;
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, bitmap.slot)
            let offset := and(0xff, begin)
            let base := and(keccak256(0x00, 0x20), not(0x7f))
            negBits := shl(offset, shr(offset, not(sload(add(base, bucket))))) // not(sload(add(base, bucket))) >> offset << offset
            if iszero(negBits) {
                let lastBucket := shr(8, upTo)
                for {} 1 {} {
                    bucket := add(bucket, 1)
                    negBits := not(sload(add(base, bucket)))
                    if or(negBits, gt(bucket, lastBucket)) { break }
                }
                if gt(bucket, lastBucket) {
                    negBits := shl(and(0xff, not(upTo)), shr(and(0xff, not(upTo)), negBits))
                }
            }
        }
        if (negBits != 0) {
            uint256 r = (bucket << 8) | LibBit.ffs(negBits);
            /// @solidity memory-safe-assembly
            assembly {
                unsetBitIndex := or(r, sub(0, or(gt(r, upTo), lt(r, begin))))
            }
        }
    }
}
