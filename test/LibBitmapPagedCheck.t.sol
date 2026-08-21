// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

// Temporary soundness check for paged setBatch/unsetBatch.
// Validates via get() round-trips only, independent of test fixtures.
import "./utils/SoladyTest.sol";
import {LibBitmap} from "../src/utils/LibBitmap.sol";

contract LibBitmapPagedCheckTest is SoladyTest {
    using LibBitmap for LibBitmap.Bitmap;

    LibBitmap.Bitmap bitmap;

    function _checkRange(uint256 start, uint256 amount, uint256 pad) internal {
        // Set sentinels just outside the range.
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
        // Sentinels must survive both ops.
        if (start >= 1) assertTrue(bitmap.get(start - 1), "clobbered bit below range");
        assertTrue(bitmap.get(start + amount), "clobbered bit above range");
        // Nearby padding must remain untouched.
        for (uint256 i = 1; i <= pad; ++i) {
            assertFalse(bitmap.get(start + amount + i), "wrote above range");
            if (start > i) assertFalse(bitmap.get(start - 1 - i), "wrote below range");
        }
    }

    function testCrossPageBatch() public {
        _checkRange(32000, 2000, 300); // page 0 -> page 1
        _checkRange(65530, 12, 300); // page 1 -> page 2, tiny straddle
        _checkRange(32768 * 3 - 256, 32768 + 512, 300); // spans > 1 full page
        _checkRange(5, 10, 4); // single word
        _checkRange(0, 257, 300); // word boundary + 1
        _checkRange(32768 * 5, 0, 4); // amount = 0 no-op
        _checkRange(700, 512, 300); // exact word multiples, in-page
    }

    function testFuzzBatchRoundTrip(uint256 start, uint256 amount) public {
        start = _bound(start, 0, 1 << 20);
        amount = _bound(amount, 0, 5000);
        _checkRange(start, amount, 64);
    }

    function testPopCountCrossPage() public {
        bitmap.setBatch(32000, 2000); // page 0 -> page 1
        assertEq(bitmap.popCount(32000, 2000), 2000);
        assertEq(bitmap.popCount(31000, 4000), 2000); // superset
        assertEq(bitmap.popCount(32500, 100), 100); // interior subset
        assertEq(bitmap.popCount(0, 32000), 0); // all below
        assertEq(bitmap.popCount(34000, 5000), 0); // all above
        assertEq(bitmap.popCount(32767, 2), 2); // page boundary straddle
    }

    function testPopCountTwoWordRange() public {
        bitmap.setBatch(0, 257); // exactly two words, the overcount case
        assertEq(bitmap.popCount(0, 257), 257);
        assertEq(bitmap.popCount(0, 512), 257);
        assertEq(bitmap.popCount(0, 0), 0);
    }

    function testFindLastSetCrossPage() public {
        uint256 nf = LibBitmap.NOT_FOUND;
        assertEq(bitmap.findLastSet(100000), nf); // empty map
        bitmap.set(40000); // page 1
        assertEq(bitmap.findLastSet(50000), 40000); // descend within page 1
        assertEq(bitmap.findLastSet(40000), 40000); // exact hit
        assertEq(bitmap.findLastSet(39999), nf); // below the only bit, cross to page 0
        bitmap.set(10); // page 0
        assertEq(bitmap.findLastSet(39999), 10); // full page-boundary descent
        bitmap.set(32767); // last bit of page 0
        assertEq(bitmap.findLastSet(32768), 32767); // straddle: probe page 1, find page 0
        assertEq(bitmap.findLastSet(32767), 32767);
        assertEq(bitmap.findLastSet(32766), 10); // masked out in own word
        bitmap.set(0);
        assertEq(bitmap.findLastSet(9), 0);
        bitmap.unset(0);
        assertEq(bitmap.findLastSet(9), nf);
    }

    function testFuzzFindLastSet(uint256 index, uint256 upTo) public {
        index = _bound(index, 0, 1 << 17); // 4 pages
        upTo = _bound(upTo, 0, 1 << 17);
        bitmap.set(index);
        uint256 expected = index <= upTo ? index : LibBitmap.NOT_FOUND;
        assertEq(bitmap.findLastSet(upTo), expected);
    }

    function testFindFirstUnsetCrossPage() public {
        uint256 nf = LibBitmap.NOT_FOUND;
        assertEq(bitmap.findFirstUnset(0, 100000), 0); // empty map
        bitmap.setBatch(0, 256); // word 0 fully set
        assertEq(bitmap.findFirstUnset(0, 1000), 256); // begin in bucket 0, page 0
        assertEq(bitmap.findFirstUnset(5, 1000), 256);
        bitmap.setBatch(0, 32768); // page 0 fully set
        assertEq(bitmap.findFirstUnset(0, 100000), 32768); // cross into page 1 bucket 0
        assertEq(bitmap.findFirstUnset(32512, 100000), 32768); // begin in last bucket of page 0
        assertEq(bitmap.findFirstUnset(0, 32767), nf); // bounded: old infinite-loop case
        assertEq(bitmap.findFirstUnset(0, 40000), 32768);
        bitmap.setBatch(32768, 100); // partial next page
        assertEq(bitmap.findFirstUnset(0, 100000), 32868);
        bitmap.unset(70000);
        assertEq(bitmap.findFirstUnset(70000, 70000), 70000); // begin == upTo
        assertEq(bitmap.findFirstUnset(70001, 70000), nf); // begin > upTo
    }

    function testFuzzFindFirstUnset(uint256 hole, uint256 begin, uint256 upTo) public {
        hole = _bound(hole, 0, 1 << 17);
        begin = _bound(begin, 0, 1 << 17);
        upTo = _bound(upTo, begin, 1 << 17);
        uint256 fillEnd = upTo + 300; // cover the range, leave storage zero beyond
        bitmap.setBatch(0, fillEnd);
        bitmap.unset(hole);
        uint256 expected = (hole >= begin && hole <= upTo) ? hole : LibBitmap.NOT_FOUND;
        assertEq(bitmap.findFirstUnset(begin, upTo), expected);
    }

    function testFuzzPopCount(uint256 start, uint256 amount) public {
        start = _bound(start, 0, 1 << 20);
        amount = _bound(amount, 1, 5000);
        bitmap.setBatch(start, amount);
        assertEq(bitmap.popCount(start, amount), amount);
        if (start >= 256) assertEq(bitmap.popCount(start - 256, amount + 512), amount);
    }
}
