#include "exercises.h"
#include <iostream>
#include <array>
using namespace std;

void exercise10()
{
	int i = 0;
	float average;
	array <float, 3> record_list;
	for (; i < 3; i++)
	{
		cout << "Enter your 30m scores to me:";
		cin >> record_list[i];
	}
	cout << "your average is " << (record_list[0] + record_list[1] + record_list[2]) / 3 << endl;
}