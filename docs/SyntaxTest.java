// シンタックスハイライトのテスト用ファイル
package com.example;

/* これはブロックコメントです
   複数行にまたがる */
public class SyntaxTest {
    private final String name = "SakuraMac";
    private int count = 42;

    public static void main(String[] args) {
        int value = 0x1F; // 行コメント
        if (value > 10) {
            System.out.println("Hello, " + name);
        }
    }
}
