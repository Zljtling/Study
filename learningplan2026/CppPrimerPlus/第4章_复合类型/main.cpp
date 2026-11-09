#include "exercises.h"
#include <iostream>
#include <limits>
#include <windows.h>

int main()
{
    SetConsoleOutputCP(CP_UTF8);
    SetConsoleCP(CP_UTF8);

    // 完成某道题并将对应的 cpp 加入项目后，把 nullptr 改成 exercise2 等函数名。
    void (*exercises[10])() = {
        exercise1,
        exercise2,
        exercise3,
        exercise4,
        exercise5,
        exercise6,
        exercise7,
        exercise8,
        exercise9,
        exercise10
    };

    while (true) {
        std::cout << "\n===== 第4章：复合类型 =====\n";
        for (int i = 0; i < 10; ++i) {
            std::cout << i + 1 << ". 练习题 " << i + 1;
            if (exercises[i] == nullptr) {
                std::cout << "（尚未完成）";
            }
            std::cout << '\n';
        }
        std::cout << "0. 退出程序\n请选择：";

        int choice = 0;
        if (!(std::cin >> choice)) {
            if (std::cin.eof()) {
                break;
            }
            std::cin.clear();
            std::cin.ignore((std::numeric_limits<std::streamsize>::max)(), '\n');
            std::cout << "请输入 0 到 10 之间的整数。\n";
            continue;
        }

        // 清除菜单输入留下的换行，避免练习中的 getline 直接读到空行。
        std::cin.ignore((std::numeric_limits<std::streamsize>::max)(), '\n');

        if (choice == 0) {
            break;
        }
        if (choice < 1 || choice > 10) {
            std::cout << "无效选择，请输入 0 到 10 之间的整数。\n";
            continue;
        }
        if (exercises[choice - 1] == nullptr) {
            std::cout << "练习题 " << choice << " 尚未完成，请选择其他题目。\n";
            continue;
        }

        exercises[choice - 1]();
    }

    std::cout << "程序退出。\n";
    return 0;
}
