#include "exercises.h"
#include <iostream>
#include <string>
using namespace std;

void exercise5()
{
	struct CandyBar
	{
		char brand[20];
		float weight;
		unsigned int calorie;
	};

	CandyBar snack = { "Mocha Munch", 2.3, 350 };
	cout << snack.brand << " " << snack.weight << " " << snack.calorie << endl;
}