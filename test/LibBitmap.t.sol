// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./utils/SoladyTest.sol";
import {LibBitmap} from "../src/utils/LibBitmap.sol";
import {LibBit} from "../src/utils/LibBit.sol";

contract LibBitmapTest is SoladyTest {
    using LibBitmap for LibBitmap.Bitmap;

    error AlreadyClaimed();

    LibBitmap.Bitmap bitmap;

    function get(uint256 index) public view returns (bool result) {
        result = bitmap.get(index);
    }

    function set(uint256 index) public {
        bitmap.set(index);
    }

    function unset(uint256 index) public {
        bitmap.unset(index);
    }

    function toggle(uint256 index) public {
        bitmap.toggle(index);
    }

    function setTo(uint256 index, bool shouldSet) public {
        bitmap.setTo(index, shouldSet);
    }

    function claimWithGetSet(uint256 index) public {
        if (bitmap.get(index)) {
            revert AlreadyClaimed();
        }
        bitmap.set(index);
    }

    function claimWithToggle(uint256 index) public {
        if (bitmap.toggle(index) == false) {
            revert AlreadyClaimed();
        }
    }

    function testBitmapGet() public {
        testBitmapGet(111111);
    }

    function testBitmapGet(uint256 index) public {
        assertFalse(get(index));
    }

    function testBitmapSetAndGet(uint256 index) public {
        set(index);
        bool result = get(index);
        bool resultIsOne;
        /// @solidity memory-safe-assembly
        assembly {
            resultIsOne := eq(result, 1)
        }
        assertTrue(result);
        assertTrue(resultIsOne);
    }

    function testBitmapSet() public {
        testBitmapSet(222222);
    }

    function testBitmapSet(uint256 index) public {
        set(index);
        assertTrue(get(index));
    }

    function testBitmapUnset() public {
        testBitmapSet(333333);
    }

    function testBitmapUnset(uint256 index) public {
        set(index);
        assertTrue(get(index));
        unset(index);
        assertFalse(get(index));
    }

    function testBitmapSetTo() public {
        testBitmapSetTo(555555, true, 0);
        testBitmapSetTo(555555, false, 0);
    }

    function testBitmapSetTo(uint256 index, bool shouldSet, uint256 randomness) public {
        bool shouldSetBrutalized;
        /// @solidity memory-safe-assembly
        assembly {
            if shouldSet { shouldSetBrutalized := or(iszero(randomness), randomness) }
        }
        setTo(index, shouldSetBrutalized);
        assertEq(get(index), shouldSet);
    }

    function testBitmapSetTo(uint256 index, uint256 randomness) public {
        randomness = _random();
        unchecked {
            for (uint256 i; i < 5; ++i) {
                bool shouldSet;
                /// @solidity memory-safe-assembly
                assembly {
                    shouldSet := and(shr(i, randomness), 1)
                }
                testBitmapSetTo(index, shouldSet, _random());
            }
        }
    }

    function testBitmapToggle() public {
        testBitmapToggle(777777, true);
        testBitmapToggle(777777, false);
    }

    function testBitmapToggle(uint256 index, bool initialValue) public {
        setTo(index, initialValue);
        assertEq(get(index), initialValue);
        toggle(index);
        assertEq(get(index), !initialValue);
    }

    function testBitmapClaimWithGetSet() public {
        uint256 index = 888888;
        this.claimWithGetSet(index);
        vm.expectRevert(AlreadyClaimed.selector);
        this.claimWithGetSet(index);
    }

    function testBitmapClaimWithToggle() public {
        uint256 index = 999999;
        this.claimWithToggle(index);
        vm.expectRevert(AlreadyClaimed.selector);
        this.claimWithToggle(index);
    }

    function testBitmapSetBatchWithinSingleBucket() public {
        _testBitmapSetBatch(257, 30);
    }

    function testBitmapSetBatchAcrossMultipleBuckets() public {
        _testBitmapSetBatch(10, 512);
    }

    function testBitmapSetBatch() public {
        unchecked {
            for (uint256 i; i < 8; ++i) {
                uint256 start = _random();
                uint256 amount = _random();
                _testBitmapSetBatch(start, amount);
            }
        }
    }

    function testBitmapUnsetBatchWithinSingleBucket() public {
        _testBitmapUnsetBatch(257, 30);
    }

    function testBitmapUnsetBatchAcrossMultipleBuckets() public {
        _testBitmapUnsetBatch(10, 512);
    }

    function testBitmapUnsetBatch() public {
        unchecked {
            for (uint256 i; i < 8; ++i) {
                uint256 start = _random();
                uint256 amount = _random();
                _testBitmapUnsetBatch(start, amount);
            }
        }
    }

    function testBitmapPopCountWithinSingleBucket() public {
        _testBitmapPopCount(1, 150);
    }

    function testBitmapPopCountAcrossMultipleBuckets() public {
        _testBitmapPopCount(10, 512);
    }

    function testBitmapPopCount(uint256, uint256 start, uint256 amount) public {
        unchecked {
            uint256 n = 1000;
            uint256 expectedCount;
            _resetBitmap(0, n / 256 + 1);

            (start, amount) = _boundStartAndAmount(start, amount, n);

            uint256 jPrev = 0xff + 1;
            uint256 j = _random() & 0xff;
            while (true) {
                bitmap.set(j);
                if (j != jPrev && start <= j && j < start + amount) {
                    expectedCount += 1;
                }
                if (start + amount <= j && _random() & 7 == 0) break;
                jPrev = j;
                j += _random() & 0xff;
            }
            assertEq(bitmap.popCount(start, amount), expectedCount);
        }
    }

    function testBitmapPopCount() public {
        unchecked {
            for (uint256 i; i < 8; ++i) {
                uint256 start = _random();
                uint256 amount = _random();
                testBitmapPopCount(start, amount, _random());
            }
        }
    }

    function testBitmapFindFirstUnset() public {
        assertEq(bitmap.findFirstUnset(0, 1000), 0);
        assertEq(bitmap.findFirstUnset(1, 1000), 1);
        assertEq(bitmap.findFirstUnset(255, 1000), 255);
        assertEq(bitmap.findFirstUnset(256, 1000), 256);
        bitmap.set(0);
        assertEq(bitmap.findFirstUnset(0, 1000), 1);
        _setBucket(0, type(uint256).max);
        assertEq(bitmap.findFirstUnset(0, 1000), 256);
        bitmap.set(256);
        assertEq(bitmap.findFirstUnset(0, 1000), 257);
        assertEq(bitmap.findFirstUnset(0, 255), LibBitmap.NOT_FOUND);
        assertEq(bitmap.findFirstUnset(0, 256), LibBitmap.NOT_FOUND);
        assertEq(bitmap.findFirstUnset(0, 257), 257);
        assertEq(bitmap.findFirstUnset(10, 9), LibBitmap.NOT_FOUND);
        assertEq(bitmap.findFirstUnset(1000, 9), LibBitmap.NOT_FOUND);
    }

    function testBitmapFindFirstUnset(uint256 begin, uint256 upTo, bytes32) public {
        unchecked {
            for (uint256 i; i != 5; ++i) {
                _setBucket(i, type(uint256).max);
            }
        }

        do {
            begin = _bound(_random(), 0, 1000);
            upTo = _bound(_random(), 0, 1000);
        } while (begin > upTo);

        uint256 expected = _bound(_random(), 0, 1000);
        bitmap.unset(expected);
        assertEq(
            bitmap.findFirstUnset(begin, upTo),
            expected < begin || expected > upTo ? LibBitmap.NOT_FOUND : expected
        );

        while (_randomChance(4)) {
            uint256 nextExpected = _bound(_random(), 0, 1000);
            bitmap.unset(nextExpected);
            if (nextExpected < expected) expected = nextExpected;
            assertEq(bitmap.findFirstUnset(0, 1000), expected);
        }

        if (_randomChance(8)) {
            do {
                begin = _bound(_random(), 0, 1000);
                upTo = _bound(_random(), 0, 1000);
            } while (begin <= upTo);

            assertEq(bitmap.findFirstUnset(begin, upTo), LibBitmap.NOT_FOUND);
        }
    }

    function testBitmapFindLastSet() public {
        unchecked {
            bitmap.unsetBatch(0, 2000);
            bitmap.set(1000);
            for (uint256 i = 0; i < 1000; ++i) {
                assertEq(bitmap.findLastSet(i), LibBitmap.NOT_FOUND);
            }
            bitmap.set(100);
            bitmap.set(10);
            for (uint256 i = 0; i < 10; ++i) {
                assertEq(bitmap.findLastSet(i), LibBitmap.NOT_FOUND);
            }
            for (uint256 i = 10; i < 100; ++i) {
                assertEq(bitmap.findLastSet(i), 10);
            }
            for (uint256 i = 100; i < 600; ++i) {
                assertEq(bitmap.findLastSet(i), 100);
            }
            for (uint256 i = 1000; i < 1100; ++i) {
                assertEq(bitmap.findLastSet(i), 1000);
            }
            bitmap.set(0);
            for (uint256 i = 0; i < 10; ++i) {
                assertEq(bitmap.findLastSet(i), 0);
            }
        }
    }

    function testBitmapFindLastSet2() public {
        unchecked {
            assertEq(bitmap.findLastSet(100), LibBitmap.NOT_FOUND);
            bitmap.set(0);
            assertEq(bitmap.findLastSet(100), 0);
            assertEq(bitmap.findLastSet(0), 0);
        }
    }

    function testBitmapFindLastSet(uint256 upTo, bytes32) public {
        uint256 n = 1000;
        uint256 randomness;
        unchecked {
            _resetBitmap(0, n / 256 + 1);
            upTo = upTo % n;
            randomness = _random() % n;
        }
        bitmap.set(randomness);
        if (randomness <= upTo) {
            assertEq(bitmap.findLastSet(upTo), randomness);
            uint256 nextLcg = _random();
            bitmap.set(nextLcg);
            if (nextLcg <= upTo) {
                assertEq(bitmap.findLastSet(upTo), (randomness < nextLcg ? nextLcg : randomness));
            }
        } else {
            assertEq(bitmap.findLastSet(upTo), LibBitmap.NOT_FOUND);
            uint256 nextLcg = _random();
            bitmap.set(nextLcg);
            if (nextLcg <= upTo) {
                assertEq(bitmap.findLastSet(upTo), nextLcg);
            } else {
                assertEq(bitmap.findLastSet(upTo), LibBitmap.NOT_FOUND);
            }
        }
    }

    function testBitmapBatchCrossPage() public {
        _checkBatchRange(32000, 2000, 300); // Page 0 -> page 1.
        _checkBatchRange(65530, 12, 300); // Page 1 -> page 2, tiny straddle.
        _checkBatchRange(32768 * 3 - 256, 32768 + 512, 300); // Spans more than 1 full page.
        _checkBatchRange(5, 10, 4); // Single word.
        _checkBatchRange(0, 257, 300); // Word boundary + 1.
        _checkBatchRange(32768 * 5, 0, 4); // `amount = 0` no-op.
        _checkBatchRange(700, 512, 300); // Exact word multiples, in-page.
    }

    function testBitmapBatchCrossPage(uint256 start, uint256 amount) public {
        start = _bound(start, 0, 1 << 20);
        amount = _bound(amount, 0, 5000);
        _checkBatchRange(start, amount, 64);
    }

    function testBitmapPopCountCrossPage() public {
        bitmap.setBatch(32000, 2000); // Page 0 -> page 1.
        assertEq(bitmap.popCount(32000, 2000), 2000);
        assertEq(bitmap.popCount(31000, 4000), 2000); // Superset.
        assertEq(bitmap.popCount(32500, 100), 100); // Interior subset.
        assertEq(bitmap.popCount(0, 32000), 0); // All below.
        assertEq(bitmap.popCount(34000, 5000), 0); // All above.
        assertEq(bitmap.popCount(32767, 2), 2); // Page boundary straddle.
    }

    function testBitmapPopCountCrossPage(uint256 start, uint256 amount) public {
        start = _bound(start, 0, 1 << 20);
        amount = _bound(amount, 1, 5000);
        bitmap.setBatch(start, amount);
        assertEq(bitmap.popCount(start, amount), amount);
        if (start >= 256) assertEq(bitmap.popCount(start - 256, amount + 512), amount);
    }

    function testBitmapPopCountTwoWordRange() public {
        bitmap.setBatch(0, 257); // Exactly two words.
        assertEq(bitmap.popCount(0, 257), 257);
        assertEq(bitmap.popCount(0, 512), 257);
        assertEq(bitmap.popCount(0, 0), 0);
    }

    function testBitmapFindLastSetCrossPage() public {
        uint256 nf = LibBitmap.NOT_FOUND;
        assertEq(bitmap.findLastSet(100000), nf); // Empty map.
        bitmap.set(40000); // Page 1.
        assertEq(bitmap.findLastSet(50000), 40000); // Descend within page 1.
        assertEq(bitmap.findLastSet(40000), 40000); // Exact hit.
        assertEq(bitmap.findLastSet(39999), nf); // Below the only bit, cross to page 0.
        bitmap.set(10); // Page 0.
        assertEq(bitmap.findLastSet(39999), 10); // Full page-boundary descent.
        bitmap.set(32767); // Last bit of page 0.
        assertEq(bitmap.findLastSet(32768), 32767); // Straddle: probe page 1, find page 0.
        assertEq(bitmap.findLastSet(32767), 32767);
        assertEq(bitmap.findLastSet(32766), 10); // Masked out in own word.
        bitmap.set(0);
        assertEq(bitmap.findLastSet(9), 0);
        bitmap.unset(0);
        assertEq(bitmap.findLastSet(9), nf);
    }

    function testBitmapFindLastSetCrossPage(uint256 index, uint256 upTo) public {
        index = _bound(index, 0, 1 << 17); // 4 pages.
        upTo = _bound(upTo, 0, 1 << 17);
        bitmap.set(index);
        uint256 expected = index <= upTo ? index : LibBitmap.NOT_FOUND;
        assertEq(bitmap.findLastSet(upTo), expected);
    }

    function testBitmapFindFirstUnsetCrossPage() public {
        uint256 nf = LibBitmap.NOT_FOUND;
        assertEq(bitmap.findFirstUnset(0, 100000), 0); // Empty map.
        bitmap.setBatch(0, 256); // Word 0 fully set.
        assertEq(bitmap.findFirstUnset(0, 1000), 256); // Begin in bucket 0, page 0.
        assertEq(bitmap.findFirstUnset(5, 1000), 256);
        bitmap.setBatch(0, 32768); // Page 0 fully set.
        assertEq(bitmap.findFirstUnset(0, 100000), 32768); // Cross into page 1 bucket 0.
        assertEq(bitmap.findFirstUnset(32512, 100000), 32768); // Begin in last bucket of page 0.
        assertEq(bitmap.findFirstUnset(0, 32767), nf); // Bounded on a fully set page.
        assertEq(bitmap.findFirstUnset(0, 40000), 32768);
        bitmap.setBatch(32768, 100); // Partial next page.
        assertEq(bitmap.findFirstUnset(0, 100000), 32868);
        bitmap.unset(70000);
        assertEq(bitmap.findFirstUnset(70000, 70000), 70000); // `begin == upTo`.
        assertEq(bitmap.findFirstUnset(70001, 70000), nf); // `begin > upTo`.
    }

    function testBitmapFindFirstUnsetCrossPage(uint256 hole, uint256 begin, uint256 upTo) public {
        hole = _bound(hole, 0, 1 << 17);
        begin = _bound(begin, 0, 1 << 17);
        upTo = _bound(upTo, begin, 1 << 17);
        bitmap.setBatch(0, upTo + 300); // Cover the range, leave storage zero beyond.
        bitmap.unset(hole);
        uint256 expected = (hole >= begin && hole <= upTo) ? hole : LibBitmap.NOT_FOUND;
        assertEq(bitmap.findFirstUnset(begin, upTo), expected);
    }

    /// @dev Round-trips `setBatch` and `unsetBatch` over `[start, start + amount)`
    /// via `get`, with sentinel bits just outside the range and `pad` bits of
    /// padding checked for stray writes.
    function _checkBatchRange(uint256 start, uint256 amount, uint256 pad) internal {
        if (start >= 1) bitmap.set(start - 1);
        bitmap.set(start + amount);
        bitmap.setBatch(start, amount);
        for (uint256 i = start; i < start + amount; ++i) {
            assertTrue(bitmap.get(i), "setBatch missed a bit");
        }
        bitmap.unsetBatch(start, amount);
        for (uint256 i = start; i < start + amount; ++i) {
            assertFalse(bitmap.get(i), "unsetBatch missed a bit");
        }
        if (start >= 1) assertTrue(bitmap.get(start - 1), "clobbered bit below range");
        assertTrue(bitmap.get(start + amount), "clobbered bit above range");
        for (uint256 i = 1; i <= pad; ++i) {
            assertFalse(bitmap.get(start + amount + i), "wrote above range");
            if (start > i) assertFalse(bitmap.get(start - 1 - i), "wrote below range");
        }
    }

    function _testBitmapSetBatch(uint256 start, uint256 amount) internal {
        uint256 n = 1000;
        (start, amount) = _boundStartAndAmount(start, amount, n);

        unchecked {
            _resetBitmap(0, n / 256 + 1);
            bitmap.setBatch(start, amount);
            for (uint256 i; i < n; ++i) {
                if (i < start) {
                    assertFalse(bitmap.get(i));
                } else if (i < start + amount) {
                    assertTrue(bitmap.get(i));
                } else {
                    assertFalse(bitmap.get(i));
                }
            }
        }
    }

    function _testBitmapUnsetBatch(uint256 start, uint256 amount) internal {
        uint256 n = 1000;
        (start, amount) = _boundStartAndAmount(start, amount, n);

        unchecked {
            _resetBitmap(type(uint256).max, n / 256 + 1);
            bitmap.unsetBatch(start, amount);
            for (uint256 i; i < n; ++i) {
                if (i < start) {
                    assertTrue(bitmap.get(i));
                } else if (i < start + amount) {
                    assertFalse(bitmap.get(i));
                } else {
                    assertTrue(bitmap.get(i));
                }
            }
        }
    }

    function _testBitmapPopCount(uint256 start, uint256 amount) internal {
        uint256 n = 1000;
        (start, amount) = _boundStartAndAmount(start, amount, n);

        unchecked {
            _resetBitmap(0, n / 256 + 1);
            bitmap.setBatch(start, amount);
            assertEq(bitmap.popCount(0, n), amount);
            if (start > 0) {
                assertEq(bitmap.popCount(0, start - 1), 0);
            }
            if (start + amount < n) {
                assertEq(bitmap.popCount(start + amount, n - (start + amount)), 0);
            }
        }
    }

    function _boundStartAndAmount(uint256 start, uint256 amount, uint256 n)
        private
        pure
        returns (uint256 boundedStart, uint256 boundedAmount)
    {
        unchecked {
            boundedStart = start % n;
            uint256 end = boundedStart + (amount % n);
            if (end > n) end = n;
            boundedAmount = end - boundedStart;
        }
    }

    function _resetBitmap(uint256 bucketValue, uint256 bucketEnd) private {
        unchecked {
            for (uint256 i; i < bucketEnd; ++i) {
                _setBucket(i, bucketValue);
            }
        }
    }

    /// @dev Writes a bucket directly, mirroring the library's paged layout:
    /// word `bucket` lives at `keccak256(bucket >> 7, slot) & ~0x7f` + `bucket & 0x7f`.
    function _setBucket(uint256 bucket, uint256 value) private {
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, shr(7, bucket))
            mstore(0x20, bitmap.slot)
            sstore(add(and(keccak256(0x00, 0x40), not(0x7f)), and(bucket, 0x7f)), value)
        }
    }
}
